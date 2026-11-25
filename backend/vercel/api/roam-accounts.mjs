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
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS referral_source text NOT NULL DEFAULT '';
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS referral_handle text NOT NULL DEFAULT '';
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS profile_photo text NOT NULL DEFAULT '';
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS share_location boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS last_seen timestamptz;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS app_active boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS latitude double precision;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS longitude double precision;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS is_spoofing boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS location_updated_at timestamptz;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS community_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS community_blocked boolean NOT NULL DEFAULT false;
ALTER TABLE roam_accounts ADD COLUMN IF NOT EXISTS community_keep_for_owner boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS roam_sessions (
 digest text PRIMARY KEY, account_id uuid REFERENCES roam_accounts(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS roam_messages (
 id uuid PRIMARY KEY, recipient_id uuid NOT NULL REFERENCES roam_accounts(id) ON DELETE CASCADE,
 body text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS roam_broadcasts (id uuid PRIMARY KEY, body text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE roam_messages ADD COLUMN IF NOT EXISTS broadcast_id uuid REFERENCES roam_broadcasts(id);
CREATE UNIQUE INDEX IF NOT EXISTS roam_broadcast_recipient ON roam_messages(broadcast_id,recipient_id);
CREATE INDEX IF NOT EXISTS roam_message_recipient ON roam_messages(recipient_id,created_at DESC);
CREATE TABLE IF NOT EXISTS roam_safety_reports (
 id uuid PRIMARY KEY, account_id uuid REFERENCES roam_accounts(id) ON DELETE CASCADE,
 destination text NOT NULL CHECK(length(destination) BETWEEN 3 AND 1000),
 kind text NOT NULL CHECK(kind IN ('fixed','driving','walking','cycling')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS roam_safety_user ON roam_safety_reports(account_id,created_at DESC);
CREATE TABLE IF NOT EXISTS roam_limits (bucket text NOT NULL,window_id bigint NOT NULL,count int NOT NULL,PRIMARY KEY(bucket,window_id));
`;
const fields=`id,username,email,tiktok,instagram,referral_source,referral_handle,profile_photo,share_location,community_enabled,community_blocked,community_keep_for_owner,last_seen,CASE WHEN share_location THEN latitude ELSE NULL END AS latitude,CASE WHEN share_location THEN longitude ELSE NULL END AS longitude,CASE WHEN share_location THEN is_spoofing ELSE false END AS is_spoofing,CASE WHEN share_location THEN location_updated_at ELSE NULL END AS location_updated_at,(app_active AND last_seen > now() - interval '45 seconds') AS is_active,false AS is_owner`;
const owner=()=>({id:'00000000-0000-4000-8000-000000000001',username:'Owner',email:process.env.ROAM_OWNER_EMAIL,tiktok:'',instagram:'',is_owner:true});
function photo(value){
 check(typeof value==='string'&&value.length<=80000,'Photo is too large. Choose a smaller photo.');
 check(value===''||(/^\/9j\/[A-Za-z0-9+/=]+$/.test(value)&&Buffer.from(value,'base64').subarray(0,3).equals(Buffer.from([255,216,255]))),'Use a JPEG profile photo.');
 return value;
}
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
  await db.query('INSERT INTO roam_sessions VALUES($1,$2,$3)',[digest(token),id,new Date(Date.now()+30*86400000)]);
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
   check(Buffer.byteLength(JSON.stringify(b))<=180000,'Request too large.',413);
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
     const source=typeof b.referral_source==='string'?b.referral_source:'';
     const handle=typeof b.referral_handle==='string'?b.referral_handle.trim():'';
     const referralForm = Object.hasOwn(b,'referral_source') || Object.hasOwn(b,'referral_handle');
     check(!referralForm || ['TikTok','Instagram','LinkedIn','Resume'].includes(source),'Choose how you heard about the app. Update the app if this field is missing.');
     check(!referralForm || /^@?[A-Za-z0-9_.-]{1,100}$/.test(handle),'Enter your social @ or LinkedIn handle, using letters, numbers, dots, underscores or hyphens.');
     const picture=photo(b.profile_photo??'');
     const share=b.share_location===true;
     const salt=randomBytes(16).toString('hex'),hash=(await derive(b.password,salt,64)).toString('hex');
     const {rows:[profile]}=await db.query('INSERT INTO roam_accounts(id,email,username,tiktok,instagram,salt,hash,referral_source,referral_handle,profile_photo,share_location,last_seen) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,now()) ON CONFLICT(email) DO NOTHING RETURNING '+fields,[randomUUID(),email,username,tiktok,instagram,salt,hash,source,handle,picture,share]);
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
   await limit((b.action==='inbox'?'inbox:':'session:')+digest(token),b.action==='inbox'?180:500);
   if(b.action==='signout'){await db.query('DELETE FROM roam_sessions WHERE digest=$1',[digest(token)]);return reply(200,{ok:true});}
   if(b.action==='inbox'){
    const offset=Number(b.offset||0);check(Number.isSafeInteger(offset)&&offset>=0,'Invalid inbox offset.');
    if(session.account_id===null){
     const {rows:messages}=await db.query(`SELECT s.id,'Destination report from '||COALESCE(a.username,'Owner')||E'\\n'||s.destination||E'\\nFor: '||s.kind AS body,
       s.created_at,s.account_id AS subject_user_id,true AS is_safety_report
       FROM roam_safety_reports s LEFT JOIN roam_accounts a ON a.id=s.account_id
       ORDER BY s.created_at DESC,s.id DESC LIMIT 100 OFFSET $1`,[offset]);
     return reply(200,{messages});
    }
    const {rows:messages}=await db.query('SELECT id,body,created_at FROM roam_messages WHERE recipient_id=$1 ORDER BY created_at DESC,id DESC LIMIT 100 OFFSET $2',[session.account_id,offset]);
    return reply(200,{messages});
   }
   if(b.action==='status'){
    const profile=session.account_id===null?owner():(await db.query('SELECT '+fields+' FROM roam_accounts WHERE id=$1',[session.account_id])).rows[0];
    check(profile,'Account no longer available.',401);
    const messages=session.account_id?(await db.query('SELECT id,body,created_at FROM roam_messages WHERE recipient_id=$1 ORDER BY created_at DESC LIMIT 50',[session.account_id])).rows:[];
    return reply(200,{profile,messages});
   }
   if(b.action==='safety-submit'){
    check(typeof b.request_id==='string'&&/^[a-f0-9-]{36}$/i.test(b.request_id),'Invalid submission request.');
    const destination=typeof b.destination==='string'?b.destination.trim():'';
    check(destination.length>=3&&destination.length<=1000,'Enter your actual destination (3–1,000 characters).');
    check(['fixed','driving','walking','cycling'].includes(b.kind),'Choose a valid session type.');
    await db.query('INSERT INTO roam_safety_reports(id,account_id,destination,kind) VALUES($1,$2,$3,$4) ON CONFLICT(id) DO NOTHING',[b.request_id,session.account_id,destination,b.kind]);
    const {rows:[report]}=await db.query('SELECT id,destination,kind,created_at FROM roam_safety_reports WHERE id=$1 AND account_id IS NOT DISTINCT FROM $2',[b.request_id,session.account_id]);
    check(report&&report.destination===destination&&report.kind===b.kind,'This request was already used. Start a new submission.',409);
    return reply(200,{ok:true});
   }
   if(b.action==='presence'){
    check(session.account_id,'A user account is required.',403);
    const hasLocation=b.latitude!==undefined||b.longitude!==undefined;
    check(!hasLocation||(typeof b.latitude==='number'&&Number.isFinite(b.latitude)&&Math.abs(b.latitude)<=90&&typeof b.longitude==='number'&&Number.isFinite(b.longitude)&&Math.abs(b.longitude)<=180),'Invalid coordinates.');
    const active=b.active===true;
    // Consent is read inside this UPDATE so a stale heartbeat cannot undo an opt-out.
    const {rows:[profile]}=await db.query(`UPDATE roam_accounts SET last_seen=now(),app_active=$2,
      latitude=CASE WHEN NOT (share_location OR (community_enabled AND NOT community_blocked)) THEN NULL WHEN $3 THEN $4 ELSE latitude END,
      longitude=CASE WHEN NOT (share_location OR (community_enabled AND NOT community_blocked)) THEN NULL WHEN $3 THEN $5 ELSE longitude END,
      is_spoofing=CASE WHEN NOT (share_location OR (community_enabled AND NOT community_blocked)) THEN false WHEN $3 THEN $6 ELSE is_spoofing END,
      location_updated_at=CASE WHEN NOT (share_location OR (community_enabled AND NOT community_blocked)) THEN NULL WHEN $3 THEN now() ELSE location_updated_at END
      WHERE id=$1 RETURNING `+fields,[session.account_id,active,active&&hasLocation,b.latitude??null,b.longitude??null,b.spoofing===true]);
    return reply(200,{profile});
   }
   if(b.action==='profile-settings'){
    check(session.account_id,'A user account is required.',403);
    check(typeof b.share_location==='boolean','Choose whether to share your location.');
    const picture=b.profile_photo===undefined?null:photo(b.profile_photo);
    const {rows:[profile]}=await db.query(`UPDATE roam_accounts SET share_location=$2,profile_photo=COALESCE($3,profile_photo),
      latitude=CASE WHEN $2 OR community_enabled THEN latitude ELSE NULL END,longitude=CASE WHEN $2 OR community_enabled THEN longitude ELSE NULL END,
      is_spoofing=CASE WHEN $2 OR community_enabled THEN is_spoofing ELSE false END,location_updated_at=CASE WHEN $2 OR community_enabled THEN location_updated_at ELSE NULL END
      WHERE id=$1 RETURNING `+fields,[session.account_id,b.share_location,picture]);
    return reply(200,{profile});
   }
   if(b.action==='community-settings'){
    check(session.account_id,'Owner does not need to join the map.',403);
    check(typeof b.enabled==='boolean','Choose whether to join the Community map.');
    const {rows:[profile]}=await db.query(`UPDATE roam_accounts SET community_enabled=$2,community_keep_for_owner=($2 AND $3),
      latitude=CASE WHEN share_location OR $2 THEN latitude ELSE NULL END,
      longitude=CASE WHEN share_location OR $2 THEN longitude ELSE NULL END,
      is_spoofing=CASE WHEN share_location OR $2 THEN is_spoofing ELSE false END,
      location_updated_at=CASE WHEN share_location OR $2 THEN location_updated_at ELSE NULL END
      WHERE id=$1 AND (NOT $2 OR NOT community_blocked) RETURNING `+fields,[session.account_id,b.enabled,b.keep_for_owner===true]);
    check(profile,'Community map access has been removed by the owner.',403);
    return reply(200,{profile});
   }
   if(b.action==='community-list'){
    if(session.account_id){
     const {rows:[member]}=await db.query('SELECT community_enabled,community_blocked FROM roam_accounts WHERE id=$1',[session.account_id]);
     check(member?.community_enabled&&!member.community_blocked,'Join the Community map to see other users.',403);
    }
    const offset=Number(b.offset||0);check(Number.isSafeInteger(offset)&&offset>=0,'Invalid offset.');
    const {rows:members}=await db.query(`SELECT id,username,profile_photo,'' AS email,'' AS tiktok,'' AS instagram,
      true AS share_location,false AS is_owner,round(latitude::numeric,2)::double precision AS latitude,
      round(longitude::numeric,2)::double precision AS longitude,is_spoofing,location_updated_at,last_seen,
      (app_active AND last_seen>now()-interval '45 seconds') AS is_active
      FROM roam_accounts WHERE community_enabled AND NOT community_blocked AND latitude IS NOT NULL AND longitude IS NOT NULL
      AND (location_updated_at>now()-interval '10 minutes' OR ($2 AND community_keep_for_owner)) ORDER BY id LIMIT 40 OFFSET $1`,[offset,session.account_id===null]);
    return reply(200,{members});
   }
   check(session.account_id===null,'Owner access required.',403);
   if(b.action==='owner-profile'){
    check(typeof b.id==='string'&&/^[a-f0-9-]{36}$/i.test(b.id),'Invalid account.');
    const {rows:[profile]}=await db.query('SELECT '+fields+' FROM roam_accounts WHERE id=$1',[b.id]);
    check(profile,'Account no longer available.',404);return reply(200,{profile});
   }
   if(b.action==='safety-history'){
    check(typeof b.id==='string'&&/^[a-f0-9-]{36}$/i.test(b.id),'Invalid account.');
    const offset=Number(b.offset||0);check(Number.isSafeInteger(offset)&&offset>=0,'Invalid offset.');
    const {rows:reports}=await db.query('SELECT id,destination,kind,created_at FROM roam_safety_reports WHERE account_id=$1 ORDER BY created_at DESC,id DESC LIMIT 100 OFFSET $2',[b.id,offset]);
    return reply(200,{reports});
   }
   if(b.action==='community-remove'){
    check(typeof b.id==='string'&&/^[a-f0-9-]{36}$/i.test(b.id)&&typeof b.blocked==='boolean','Invalid community member.');
    const result=await db.query(`UPDATE roam_accounts SET community_blocked=$2,community_enabled=false,community_keep_for_owner=false,
      latitude=CASE WHEN share_location THEN latitude ELSE NULL END,longitude=CASE WHEN share_location THEN longitude ELSE NULL END,
      is_spoofing=CASE WHEN share_location THEN is_spoofing ELSE false END,
      location_updated_at=CASE WHEN share_location THEN location_updated_at ELSE NULL END WHERE id=$1`,[b.id,b.blocked]);
    check(result.rowCount,'Account not found.',404);return reply(200,{ok:true});
   }
   if(b.action==='list'){
    const offset=Number(b.offset||0);check(Number.isSafeInteger(offset)&&offset>=0,'Invalid offset.');
    return reply(200,{members:(await db.query('SELECT '+fields+' FROM roam_accounts ORDER BY created_at DESC,id LIMIT 40 OFFSET $1',[offset])).rows});
   }
   if(b.action==='broadcast'){
    const body=typeof b.body==='string'?b.body.trim():'';
    check(body.length>0&&body.length<=2000,'Message must be 1–2000 characters.');
    check(typeof b.request_id==='string'&&/^[a-f0-9-]{36}$/i.test(b.request_id),'Invalid message request.');
    await db.query(`
     WITH batch AS (
      INSERT INTO roam_broadcasts(id,body) VALUES($1,$2) ON CONFLICT(id) DO NOTHING RETURNING id
     ), sent AS (
      INSERT INTO roam_messages(id,recipient_id,body,broadcast_id)
      SELECT gen_random_uuid(),a.id,$2,batch.id FROM roam_accounts a CROSS JOIN batch RETURNING id
     ) SELECT (SELECT count(*) FROM sent)::int + (SELECT count(*) FROM roam_messages WHERE broadcast_id=$1)::int AS sent_count`,[b.request_id,body]);
    const {rows:[result]}=await db.query('SELECT body,(SELECT count(*)::int FROM roam_messages WHERE broadcast_id=$1) AS sent_count FROM roam_broadcasts WHERE id=$1',[b.request_id]);
    check(result.body===body,'This send request was already used for a different message.',409);
    return reply(200,{ok:true,sent_count:result.sent_count});
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
