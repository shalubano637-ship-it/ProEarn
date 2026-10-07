import { createClient } from "npm:@supabase/supabase-js@2";
const SUPABASE_URL=Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY=Deno.env.get("SUPABASE_ANON_KEY")!;
const IMGBB_API_KEY=Deno.env.get("IMGBB_API_KEY")!;
const IMAGE_PROXY_BASE="https://proearn-media-gateway.shalubano637.workers.dev/v1/image-proxy?url=";
const MAX_BASE64_LENGTH=12_000_000;
const CORS_HEADERS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
function b64(v:string){const n=v.replace(/-/g,"+").replace(/_/g,"/");return atob(n+"=".repeat((4-n.length%4)%4))}
function hex(b:Uint8Array){return Array.from(b).map(x=>x.toString(16).padStart(2,"0")).join("")}
function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS_HEADERS,"Content-Type":"application/json"}})}
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:CORS_HEADERS});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const auth=req.headers.get("Authorization")??"";
  const client=createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{global:{headers:{Authorization:auth}}});
  const {data:u,error:ae}=await client.auth.getUser();if(ae||!u?.user)return json({error:"Unauthorized"},401);
  const body=await req.json().catch(()=>({}));const image=String(body.imageBase64??"");const folder=String(body.folder??"posts");
  if(!image)return json({error:"imageBase64 required"},400);if(image.length>MAX_BASE64_LENGTH)return json({error:"Image too large"},400);
  // Client-side moderation runs before upload; keep storage independent of temporary AI outages.
  const form=new FormData();form.append("image",image);
  const r=await fetch(`https://api.imgbb.com/1/upload?key=${IMGBB_API_KEY}`,{method:"POST",body:form});const data=await r.json();
  if(!r.ok||!data?.data?.url){
    console.error("ImgBB upstream upload failed", r.status, data);
    const upstreamMessage =
      data?.error?.message ??
      data?.error?.error?.message ??
      data?.status_txt ??
      "ImgBB upload failed";
    return json({error:"Upload failed",details:String(upstreamMessage)},502);
  }
  const publicImageUrl = IMAGE_PROXY_BASE + data.data.url;
  if(folder!=="posts")return json({url:publicImageUrl});

  const {data:owner,error:oe}=await client.from("users").select("isPrivateAccount").eq("uid",u.user.id).maybeSingle();if(oe)return json({error:"Post privacy lookup failed"},500);

  const {data:post,error:pe}=await client.from("posts").insert({userName:u.user.id,caption:String(body.caption??"No Caption"),prompt:String(body.prompt??""),link:String(body.link??`app://post/${Date.now()}`),imageUrl:publicImageUrl,moderationStatus:"approved",moderationCheckedAt:new Date().toISOString(),moderationReason:null,mediaObjectKey:null,isPrivatePost:owner?.isPrivateAccount===true}).select().single();
  if(pe){console.error(pe);return json({error:"Post creation failed"},500)}
  return json({url:publicImageUrl,post});
 }catch(e){console.error(e);return json({error:"Internal error"},500)}
});