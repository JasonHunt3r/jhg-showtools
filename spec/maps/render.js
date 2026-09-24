const {chromium}=require('playwright');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1600,height:1200},deviceScaleFactor:2});
await p.goto('file://'+__dirname+"/maps.html");
const names={m1:'1-library-grid',m2:'2-edit-slides',m3:'3-edit-show'};
for(const id in names){await (await p.$('#'+id)).screenshot({path:__dirname+'/'+names[id]+'.png'})}
await b.close()})();
