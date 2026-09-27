import { createClient } from "npm:@supabase/supabase-js@2";
const url=Deno.env.get("SUPABASE_URL")!,key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin=createClient(url,key,{auth:{persistSession:false}});
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
Deno.serve(async request=>{
 if(request.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(request.method!=="POST")return Response.json({error:"Method not allowed"},{status:405,headers:cors});
 const body=await request.json().catch(()=>({}));const email=String(body.email??"").trim().toLowerCase();
 if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>320)return Response.json({error:"Valid email required"},{status:400,headers:cors});
 const {data:recent,error:le}=await admin.from("account_deletion_requests").select("id").eq("request_key",email).gt("created_at",new Date(Date.now()-86400000).toISOString()).limit(1).maybeSingle();
 if(le)return Response.json({error:"Request could not be submitted"},{status:500,headers:cors});
 if(recent)return Response.json({error:"Please wait before submitting another deletion request"},{status:429,headers:cors});
 const {error}=await admin.from("account_deletion_requests").insert({email,reason:String(body.reason??"").slice(0,1000),status:"pending",request_key:email});
 if(error){console.error(error);return Response.json({error:"Request could not be submitted"},{status:500,headers:cors})}
 return Response.json({success:true},{headers:cors});
});