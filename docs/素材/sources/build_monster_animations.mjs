import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execFileSync as run} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const config=JSON.parse(fs.readFileSync(path.join(root,'sources/monster_animation_v1/jobs.json'),'utf8'));
const provenancePath=path.join(root,'sources/monster_animation_v1/generation_manifest.json');
const provenance=JSON.parse(fs.readFileSync(provenancePath,'utf8'));
const magick=(args,binary=false)=>run('/opt/homebrew/bin/magick',args,{maxBuffer:64*1024*1024,...(binary?{}:{encoding:'utf8'})});
const mkdir=p=>fs.mkdirSync(p,{recursive:true});
const previewRoot=path.join(root,'previews/monster_animations_v1');mkdir(previewRoot);
const pack={version:1,created:'2026-10-14',integrated:false,generator:'built-in image_gen',direction_order:config.directions,source_layout:'columns=directions; rows=chronological frames',export_layout:'columns=chronological frames; rows=directions',actors:[]};
function bbox(pixels,w,h){let x0=w,y0=h,x1=-1,y1=-1;for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(pixels[(y*w+x)*4+3]>=154){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}assert(x1>=x0&&y1>=y0,'empty frame');return {x:x0,y:y0,w:x1-x0+1,h:y1-y0+1};}
function slice(pixels,w,x0,y0,cw,ch){const out=Buffer.alloc(cw*ch*4);for(let y=0;y<ch;y++)pixels.copy(out,y*cw*4,((y0+y)*w+x0)*4,((y0+y)*w+x0+cw)*4);return out;}
function rowBands(pixels,w,h){
 const counts=[];for(let y=0;y<h;y++){let n=0;for(let x=0;x<w;x++)if(pixels[(y*w+x)*4+3]>=154)n++;counts.push(n);}
 const peak=Math.max(...counts);let bands;
 for(const fraction of [.02,.06,.10,.14,.18,.22,.28]){
  const threshold=Math.max(10,peak*fraction),active=counts.map(n=>n>=threshold);
  for(let i=0;i<h;i++)if(!active[i]){let j=i;while(j<h&&!active[j])j++;if(i>0&&j<h&&j-i<=3)for(let k=i;k<j;k++)active[k]=true;i=j;}
  const candidate=[];let begin=-1;for(let y=0;y<=h;y++){if(active[y]&&begin<0)begin=y;if(!active[y]&&begin>=0){if(y-begin>=Math.max(20,w/32))candidate.push([begin,y]);begin=-1;}}
  if(candidate.length>=5&&candidate.length<=8&&(!bands||candidate.length>bands.length))bands=candidate;
 }
 assert(bands,'could not separate 5-8 pose rows');
 const cuts=[0];for(let i=0;i<bands.length-1;i++)cuts.push(Math.round((bands[i][1]+bands[i+1][0])/2));cuts.push(h);
 return {bands,cuts};
}
function splitActors(pixels,w,h,wanted=8){
 const label=new Int32Array(w*h).fill(-1),components=[],queue=new Int32Array(w*h);
 for(let i=0;i<w*h;i++){
  if(label[i]>=0||pixels[i*4+3]<154)continue;
  const id=components.length;let head=0,tail=0;queue[tail++]=i;label[i]=id;const indices=[];let x0=w,y0=h,x1=0,y1=0,sumx=0,sumy=0;
  while(head<tail){const k=queue[head++],x=k%w,y=Math.floor(k/w);indices.push(k);x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);sumx+=x;sumy+=y;
   for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(dx===0&&dy===0)continue;const nx=x+dx,ny=y+dy;if(nx<0||ny<0||nx>=w||ny>=h)continue;const k2=ny*w+nx;if(label[k2]<0&&pixels[k2*4+3]>=154){label[k2]=id;queue[tail++]=k2;}}
  }
  components.push({id,indices,n:indices.length,x0,y0,x1,y1,cx:sumx/indices.length,cy:sumy/indices.length});
 }
 const main=[...components].sort((a,b)=>b.n-a.n).slice(0,wanted).sort((a,b)=>a.cx-b.cx);
 if(wanted===8&&(main.length!==8||!main.every(c=>c.n>300))){
  const seams=[];
  for(let boundary=1;boundary<8;boundary++){
   const nominal=boundary*w/8,lo=Math.round(nominal-w/8*.37),hi=Math.round(nominal+w/8*.37),n=hi-lo+1;
   const back=new Int16Array(n*h);let prev=new Float64Array(n);
   for(let y=0;y<h;y++){const next=new Float64Array(n);for(let q=0;q<n;q++){
    let best=q;if(y>0){if(q>0&&prev[q-1]<prev[best])best=q-1;if(q+1<n&&prev[q+1]<prev[best])best=q+1;}
    const x=lo+q,alpha=pixels[(y*w+x)*4+3];next[q]=(y?prev[best]:0)+(alpha>=154?1000:0)+(x-nominal)**2*.015;back[y*n+q]=best;
   }prev=next;}
   let q=0;for(let k=1;k<n;k++)if(prev[k]<prev[q])q=k;const seam=new Int16Array(h);for(let y=h-1;y>=0;y--){seam[y]=lo+q;q=back[y*n+q];}seams.push(seam);
  }
  const separated=[];for(let d=0;d<8;d++){const masked=Buffer.alloc(pixels.length);for(let y=0;y<h;y++){const x0=d?seams[d-1][y]:0,x1=d<7?seams[d][y]:w;pixels.copy(masked,(y*w+x0)*4,(y*w+x0)*4,(y*w+x1)*4);}separated.push(splitActors(masked,w,h,1)[0]);}return separated;
 }
 assert(main.length===wanted&&main.every(c=>c.n>100),'missing full actor in separated direction');
 const groups=main.map(c=>[c]);
 for(const c of components){if(main.includes(c)||c.n<10)continue;let best=-1,dist=Infinity;
  for(let d=0;d<main.length;d++){const b=main[d],dx=Math.max(b.x0-c.cx,0,c.cx-b.x1),dy=Math.max(b.y0-c.cy,0,c.cy-b.y1);const score=dx*dx+dy*dy+((b.cx-c.cx)**2+(b.cy-c.cy)**2)*.001;if(score<dist){best=d;dist=score;}}
  if(dist<(w/8*.28)**2)groups[best].push(c);
 }
 return groups.map(group=>{
  const x0=Math.min(...group.map(c=>c.x0)),y0=Math.min(...group.map(c=>c.y0)),x1=Math.max(...group.map(c=>c.x1)),y1=Math.max(...group.map(c=>c.y1)),cw=x1-x0+1,ch=y1-y0+1,tile=Buffer.alloc(cw*ch*4);
  for(const c of group)for(const k of c.indices){const x=k%w-x0,y=Math.floor(k/w)-y0,p=(y*cw+x)*4;pixels.copy(tile,p,k*4,k*4+3);tile[p+3]=255;}
  return {tile,cw,ch,used:{x:0,y:0,w:cw,h:ch},sourceOffsetX:x0,sourceOffsetY:y0,unitScale:256/(w/8)};
 });
}

for(const actor of config.actors){
 const jobs=provenance.records.filter(j=>j.id===actor.id),sheets=[];
 for(const j of jobs)j.source='sources/monster_animation_v1/'+actor.id+'/'+j.state+'_source.png';
 const existing=path.join(root,'monsters',actor.id,'animations_v1/animation.json');
 if(fs.existsSync(existing)&&!process.argv.includes('--force')){pack.actors.push(JSON.parse(fs.readFileSync(existing,'utf8')));continue;}
 for(const job of jobs){
  const source=path.join(root,'sources/monster_animation_v1',actor.id,job.state+'_source.png');mkdir(path.dirname(source));if(!fs.existsSync(source))fs.copyFileSync(job.generated_path,source);
  job.source=path.relative(root,source);
  const [w,h]=magick(['identify','-format','%w %h',source]).trim().split(' ').map(Number);
  const pixels=magick([source,'-depth','8','rgba:-'],true),{bands,cuts}=rowBands(pixels,w,h);
  const frames=[];
  for(let f=0;f<bands.length;f++){
   const row=slice(pixels,w,0,cuts[f],w,cuts[f+1]-cuts[f]);
   const actors=splitActors(row,w,cuts[f+1]-cuts[f]);
   for(let d=0;d<8;d++)frames.push({f,d,...actors[d]});
  }
  sheets.push({job,source,w,h,bands,frames});
  console.log(actor.id,job.state,':',bands.length,'actual chronological frames × 8 directions');
 }
 // One common scale across ALL states/directions of each actor; no per-frame stretch or mirroring.
 const all=sheets.flatMap(s=>s.frames);
 const maxW=Math.max(...all.map(f=>f.used.w*f.unitScale)),maxH=Math.max(...all.map(f=>f.used.h*f.unitScale));
 const desired=actor.id==='boss_corrupted_beast'?[152,134]:actor.id==='elite_ash_wraith'?[84,80]:actor.id==='elite_shellback_bug'?[90,64]:[90,78];
 const scale=Math.min(desired[0]/maxW,desired[1]/maxH);
 const dir=path.join(root,'monsters',actor.id,'animations_v1');mkdir(dir);
 const info={id:actor.id,name:actor.name,frame_size:[actor.size,actor.size],pivot:actor.pivot,directions:config.directions,common_actor_scale:scale,integrated:fs.existsSync(path.resolve(root,"../../assets/sprites/monsters",actor.id,"animations.json")),generated_motion:true,procedural_rotation:false,procedural_mirroring:false,procedural_interpolation:false,states:{}};
 for(const sheet of sheets){
  const sid=sheet.job.state,state=config.states.find(s=>s.id===sid),count=sheet.bands.length;
  const stateDir=path.join(dir,sid);mkdir(stateDir);
  const arranged=[];
  for(let d=0;d<8;d++){
   const facing=config.directions[d],frameDir=path.join(stateDir,facing);mkdir(frameDir);
   const neutral=sheet.frames.find(f=>f.d===d&&f.f===0);
   const base=neutral.used,footY0=base.y+Math.floor(base.h*.8);let footSum=0,footN=0;
   for(let y=footY0;y<base.y+base.h;y++)for(let x=base.x;x<base.x+base.w;x++)if(neutral.tile[(y*neutral.cw+x)*4+3]){footSum+=x;footN++;}
   const groundRoot=(footN?footSum/footN:neutral.cw/2)+neutral.sourceOffsetX;
   const paths=[];
   for(let f=0;f<count;f++){
    const t=sheet.frames.find(t=>t.d===d&&t.f===f),u=t.used;
    const factor=t.unitScale*scale,nw=Math.max(1,Math.round(u.w*factor)),nh=Math.max(1,Math.round(u.h*factor));
    let px=Math.round(actor.pivot[0]+(u.x+t.sourceOffsetX-groundRoot)*factor),py=actor.pivot[1]-nh;
    // Clamp whole sprite into the safety canvas without ever cropping art.
    px=Math.max(2,Math.min(actor.size-nw-2,px));py=Math.max(2,Math.min(actor.size-nh-2,py));
    const raw=slice(t.tile,t.cw,u.x,u.y,u.w,u.h),tilePath=path.join(frameDir,String(f).padStart(2,'0')+'.png');
    const rawPath=path.join(root,'sources/monster_animation_v1/.working_frame.rgba');fs.writeFileSync(rawPath,raw);
    run('/opt/homebrew/bin/magick',['-size',u.w+'x'+u.h,'-depth','8','rgba:'+rawPath,'-filter','point','-resize',nw+'x'+nh+'!','-background','none','-gravity','northwest','-extent',`${actor.size}x${actor.size}-${px}-${py}`,'-define','png:color-type=6',tilePath],{maxBuffer:32*1024*1024});
    paths.push(tilePath);arranged.push(tilePath);
   }
   // GIF loops are for art review only; metadata still records non-looping attacks/hit/death.
   const gif=path.join(stateDir,facing+'_preview.gif');magick(['-delay',String(Math.round(100/state.fps)),'-dispose','background',...paths,'-loop','0',gif]);
  }
  const atlas=path.join(dir,sid+'_atlas.png');magick(['montage','-font','/System/Library/Fonts/Supplemental/Arial.ttf',...arranged,'-tile',count+'x8','-geometry',actor.size+'x'+actor.size+'+0+0','-background','none',atlas]);
  info.states[sid]={name:state.name,atlas:path.relative(root,atlas),frames_per_direction:count,total_frames:count*8,columns:count,rows:8,fps:state.fps,loop:state.loop,duration_seconds:count/state.fps,terminal_hold:!!state.terminal_hold,visual_contact_frame:sid==='stomp'?Math.min(4,count-1):state.hit?Math.min(3,count-1):null,gameplay_callbacks:false,source:sheet.job.source,actual_source_rows:sheet.bands,source_columns:8};
 }
 const idle=info.states.idle;
 const facePaths=[];
 const facingDir=path.join(dir,'directions');mkdir(facingDir);
 for(const d of config.directions){const dest=path.join(facingDir,d+'.png');fs.copyFileSync(path.join(dir,'idle',d,'00.png'),dest);facePaths.push(dest);}
 magick(['montage','-font','/System/Library/Fonts/Supplemental/Arial.ttf',...facePaths,'-tile','8x1','-geometry',actor.size+'x'+actor.size+'+0+0','-background','none',path.join(dir,'directions_atlas.png')]);
 fs.writeFileSync(path.join(dir,'animation.json'),JSON.stringify(info,null,2));pack.actors.push(info);
}
pack.integrated=pack.actors.every(a=>a.integrated);
fs.writeFileSync(path.join(previewRoot,'animation_manifest.json'),JSON.stringify(pack,null,2));
fs.writeFileSync(provenancePath,JSON.stringify(provenance,null,2));
fs.rmSync(path.join(root,'sources/monster_animation_v1/.working_frame.rgba'),{force:true});
console.log('Exported',pack.actors.reduce((n,a)=>n+Object.values(a.states).reduce((m,s)=>m+s.total_frames,0),0),'individually drawn directional frames.');
