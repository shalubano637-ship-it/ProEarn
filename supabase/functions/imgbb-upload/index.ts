import { createClient } from "npm:@supabase/supabase-js@2";
const URL=Deno.env.get("SUPABASE_URL")!, ANON=Deno.env.get("SUPABASE_ANON_KEY")!, SERVICE=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, IMGBB=Deno.env.get("IMGBB_API_KEY")!;
const GATEWAY="https://proearn-media-gateway.shalubano637.workers.dev";
const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...CORS,"Content-Type":"application/json","Cache-Control":"no-store"}});
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:CORS});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 try{
  const auth=req.headers.get("Authorization")??"";
  const client=createClient(URL,ANON,{global:{headers:{Authorization:auth}}});
  const {data:u,error:ae}=await client.auth.getUser();
  if(ae||!u?.user)return json({error:"Unauthorized"},401);
  const b=await req.json().catch(()=>({}));
  const image=String(b.imageBase64??"").replace(/^data:[^;]+;base64,/,"");
  const folder=String(b.folder??"posts");
  const type=String(b.contentType??"image/jpeg").toLowerCase();
  if(!image)return json({error:"imageBase64 required"},400);
  if(image.length>12000000)return json({error:"Image too large"},413);
  if(!["image/jpeg","image/png","image/webp"].includes(type))return json({error:"Unsupported image type"},415);
  if(!/^[A-Za-z0-9+/]*={0,2}$/.test(image))return json({error:"Invalid base64 image"},400);

  // Public feed posts must pass server moderation. Retry transient gateway/network
  // failures, but never upload a post when moderation cannot confirm it is safe.
  if(folder==="posts"){
   let mr:Response|undefined;
   let lastNetworkError:unknown;
   for(let attempt=1;attempt<=3;attempt++){
    try{
     mr=await fetch(GATEWAY+"/v1/moderate-image",{
      method:"POST",
      headers:{Authorization:auth,"Content-Type":"application/json"},
      body:JSON.stringify({imageBase64:image,contentType:type}),
     });
     if(mr.status>=500&&attempt<3){
      console.error("moderation gateway returned transient server error",mr.status,"attempt",attempt);
      await mr.body?.cancel();
      await new Promise(resolve=>setTimeout(resolve,400*attempt));
      continue;
     }
     break;
    }catch(e){
     lastNetworkError=e;
     console.error("moderation gateway request failed","attempt",attempt,String(e));
     if(attempt<3) await new Promise(resolve=>setTimeout(resolve,400*attempt));
    }
   }
   if(!mr){
    console.error("moderation gateway unreachable after retries",String(lastNetworkError));
    return json({error:"Server moderation unavailable",details:"Moderation gateway could not be reached after 3 attempts"},503);
   }
   const m=await mr.json().catch(()=>({}));
   if(!mr.ok||m?.safe!==true){
    console.error("server moderation rejected/unavailable",mr.status,m?.reason??m?.error??"no reason");
    if(mr.status===422)return json({error:m?.reason==="Server moderation unavailable"?"Server moderation temporarily unavailable":"Image rejected by server moderation",reason:m?.reason??"Content rejected"},422);
    if(mr.status===401)return json({error:"Moderation authorization failed"},401);
    return json({error:"Server moderation unavailable",details:String(m?.reason??m?.error??("Gateway HTTP "+mr.status))},503);
   }
  }

  const form=new FormData();form.append("image",image);
  let ur:Response;
  try{ur=await fetch("https://api.imgbb.com/1/upload?key="+IMGBB,{method:"POST",body:form})}
  catch(e){console.error("ImgBB network request failed",String(e));return json({error:"Image host unavailable"},502)}
  const d=await ur.json().catch(()=>({}));
  if(!ur.ok||!d?.data?.url){console.error("ImgBB upstream upload failed",ur.status,d?.error?.message??d?.status_txt);return json({error:"Upload failed",details:String(d?.error?.message??d?.status_txt??"ImgBB upload failed")},502)}
  const imageUrl=GATEWAY+"/v1/image-proxy?url="+encodeURIComponent(d.data.url);
  if(folder!=="posts")return json({url:imageUrl});

  const admin=createClient(URL,SERVICE);
  const {data:owner,error:oe}=await admin.from("users").select("isPrivateAccount").eq("uid",u.user.id).maybeSingle();
  if(oe||!owner)return json({error:"Post privacy lookup failed"},500);
  const {data:post,error:pe}=await admin.from("posts").insert({userName:u.user.id,caption:String(b.caption??"No Caption").slice(0,2000),prompt:String(b.prompt??"").slice(0,2000),link:String(b.link??("app://post/"+crypto.randomUUID())).slice(0,2000),imageUrl,moderationStatus:"approved",moderationCheckedAt:new Date().toISOString(),moderationReason:null,mediaObjectKey:null,isPrivatePost:owner.isPrivateAccount===true}).select().single();
  if(pe){console.error("post insert failed",pe);return json({error:"Post creation failed"},500)}
  return json({url:imageUrl,post});
 }catch(e){console.error("imgbb-upload error",e);return json({error:"Internal error"},500)}
});