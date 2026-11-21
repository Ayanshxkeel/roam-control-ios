import pg from 'pg';
import {createHash,randomBytes,randomUUID,scrypt,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
const derive=promisify(scrypt);
const digest=x=>createHash('sha256').update(x).digest('hex');
const same=(a,b)=>timingSafeEqual(Buffer.from(digest(a)),Buffer.from(digest(b)));
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL,max:3});
export const schema=`
CREATE TABLE IF NOT EXISTS roam_accounts (
 id uuid PRIMARY KEY, email text UNIQUE NOT NULL, username text NOT NULL,
 tiktok text NOT NULL DEFAULT '', instagram text NOT NULL DEFAULT '',
 salt text NOT NULL, hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS roam_sessions (
 digest text PRIMARY KEY, account_id uuid REFERENCES roam_accounts(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS roam_messages (
 id uuid PRIMARY KEY, recipient_id uuid NOT NULL REFERENCES roam_accounts(id) ON DELETE CASCADE,
 body text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS roam_message_recipient ON roam_messages(recipient_id,created_at DESC);
CREATE TABLE IF NOT EXISTS roam_limits (bucket text NOT NULL,window_id bigint NOT NULL,count int NOT NULL,PRIMARY KEY(bucket,window_id));
`;
const fields='id,username,email,tiktok,instagram,false AS is_owner';
const owner=()=>({id:'00000000-0000-4000-8000-000000000001',username:'Owner',email:process.env.ROAM_OWNER_EMAIL,tiktok:'',instagram:'',is_owner:true});
function check(ok,message,status=400){if(!ok)throw Object.assign(Error(message),{status});}
export function createHandler(db=pool){
 let initialized;
 async function init(){if(!initialized)initialized=db.query(schema).catch(e=>{initialized=undefined;throw e;});await initialized;}
 async function limit(bucket,max){
  const win=Math.floor(Date.now()/900000);
  const {rows:[r]}=await db.query('INSERT INTO roam_limits VALUES($1,$2,1) ON CONFLICT(bucket,window_id) DO UPDATE SET count=roam_limits.count+1 RETURNING count',[digest(bucket),win]);
  check(r.count<=max,'Too many attempts. Please try again in 15 minutes.',429);
 }
 async function issue(id){
  const token=randomBytes(32).toString('hex');
  await db.query('INSERT INTO roam_sessions VALUES($1,$2,$3)',[digest(token),id,new Date(Date.now()+(id?30*86400000:60*60000))]);
  return {token};
 }
 return async function(req,res){
  res.setHeader('Cache-Control','no-store');
  const reply=(status,data)=>res.status(status).json(data);
  if(req.method==='GET')return reply(200,{service:'roam-accounts',version:1});
  if(req.method!=='POST')return reply(405,{message:'Use POST.'});
  try{
   check(process.env.DATABASE_URL,'Accounts temporarily unavailable.',503);
   const b=typeof req.body==='string'?JSON.parse(req.body):req.body;
   check(b && typeof b==='object'&&!Array.isArray(b),'Invalid request.');
   check(Buffer.byteLength(JSON.stringify(b))<=12000,'Request too large.',413);
   await init();
   const email=typeof b.email==='string'?b.email.trim().toLowerCase():'';
   const ip=String(req.headers['x-vercel-forwarded-for']||req.socket?.remoteAddress||'unknown').split(',')[0];
   if(['signup','signin','owner-signin'].includes(b.action)){
    await limit('ip:'+ip,40);await limit('email:'+email.slice(0,254),15);
    if(b.action==='owner-signin'){
     const hashes=JSON.parse(process.env.ROAM_OWNER_HASHES||'[]');
     check(hashes.length===3&&process.env.ROAM_OWNER_EMAIL,'Owner sign-in unavailable.',503);
     check(Array.isArray(b.passwords)&&b.passwords.length===3&&b.passwords.every(p=>typeof p==='string'&&p.length>0&&p.length<=512),'Invalid owner credentials.',401);
     const valid=await Promise.all(hashes.map(async(h,i)=>same((await derive(b.passwords[i],h.salt,64)).toString('hex'),h.hash)));
     check(same(email,process.env.ROAM_OWNER_EMAIL.toLowerCase())&&valid.every(Boolean),'Invalid owner credentials.',401);
     return reply(200,{profile:owner(),...await issue(null)});
    }
    check(email.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)&&typeof b.password==='string'&&b.password.length>=8&&b.password.length<=512,'Enter a valid email and a password of 8–512 characters.');
    // Reserve the owner email; a public sign-up can never gain owner permissions.
    check(email!==(process.env.ROAM_OWNER_EMAIL||'').toLowerCase(),'Use Owner sign-in for this email.',403);
    if(b.action==='signup'){
     const username=typeof b.username==='string'?b.username.trim():'';
     const tiktok=typeof b.tiktok==='string'?b.tiktok.trim():'';
     const instagram=typeof b.instagram==='string'?b.instagram.trim():'';
     check(username.length>0&&username.length<=60&&tiktok.length<=100&&instagram.length<=100,'Check your username and social handles.');
     const salt=randomBytes(16).toString('hex'),hash=(await derive(b.password,salt,64)).toString('hex');
     const {rows:[profile]}=await db.query('INSERT INTO roam_accounts(id,email,username,tiktok,instagram,salt,hash) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(email) DO NOTHING RETURNING '+fields,[randomUUID(),email,username,tiktok,instagram,salt,hash]);
     check(profile,'An account with that email already exists.',409);
     return reply(201,{profile,...await issue(profile.id)});
    }
    const {rows:[a]}=await db.query('SELECT '+fields+',salt,hash FROM roam_accounts WHERE email=$1',[email]);
    const hash=(await derive(b.password,a?.salt||'missing-account',64)).toString('hex');
    check(a&&same(hash,a.hash),'Incorrect email or password.',401);
    const {salt,hash:stored,...profile}=a;
    return reply(200,{profile,...await issue(a.id)});
   }
   const token=String(req.headers.authorization||'').match(/^Bearer ([a-f0-9]{64})$/)?.[1];
   check(token,'Please sign in.',401);
   const {rows:[session]}=await db.query('SELECT account_id FROM roam_sessions WHERE digest=$1 AND expires_at>now()',[digest(token)]);
   check(session,'Your session has expired or your account was deleted. Please sign in.',401);
   await limit('session:'+digest(token),500);
   if(b.action==='signout'){await db.query('DELETE FROM roam_sessions WHERE digest=$1',[digest(token)]);return reply(200,{ok:true});}
   if(b.action==='status'){
    const profile=session.account_id===null?owner():(await db.query('SELECT '+fields+' FROM roam_accounts WHERE id=$1',[session.account_id])).rows[0];
    check(profile,'Account no longer available.',401);
    const messages=session.account_id?(await db.query('SELECT id,body,created_at FROM roam_messages WHERE recipient_id=$1 ORDER BY created_at DESC LIMIT 50',[session.account_id])).rows:[];
    return reply(200,{profile,messages});
   }
   check(session.account_id===null,'Owner access required.',403);
   if(b.action==='list'){
    const offset=Number(b.offset||0);check(Number.isSafeInteger(offset)&&offset>=0,'Invalid offset.');
    return reply(200,{members:(await db.query('SELECT '+fields+' FROM roam_accounts ORDER BY created_at DESC,id LIMIT 500 OFFSET $1',[offset])).rows});
   }
   check(typeof b.id==='string'&&/^[a-f0-9-]{36}$/i.test(b.id),'Invalid account.');
   if(b.action==='delete'){
    const result=await db.query('DELETE FROM roam_accounts WHERE id=$1',[b.id]);check(result.rowCount,'Account not found.',404);
    return reply(200,{ok:true});
   }
   if(b.action==='message'){
    const body=typeof b.body==='string'?b.body.trim():'';check(body.length>0&&body.length<=2000,'Message must be 1–2000 characters.');
    const result=await db.query('INSERT INTO roam_messages(id,recipient_id,body) SELECT $1,id,$3 FROM roam_accounts WHERE id=$2 RETURNING id',[randomUUID(),b.id,body]);
    check(result.rowCount,'Account not found.',404);return reply(201,{ok:true});
   }
   return reply(400,{message:'Unknown action.'});
  }catch(e){return reply(e.status||500,{message:e.status?e.message:'Account service unavailable. Please try again.'});}
 };
}
export default createHandler();
