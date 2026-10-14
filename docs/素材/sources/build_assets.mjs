import fs from 'node:fs';
import path from 'node:path';
import {execFileSync as run} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..');
const jobs=JSON.parse(fs.readFileSync(path.join(root,'sources/generation_manifest.json'),'utf8'));
const magick=(args)=>run('/opt/homebrew/bin/magick',args,{maxBuffer:10*1024*1024}).toString();
const mkdir=p=>fs.mkdirSync(p,{recursive:true});
const output=[];
for(const job of jobs){
 const source=path.join(root,'sources',job.type,job.category,job.id+'.png');mkdir(path.dirname(source));
 if(!fs.existsSync(source))fs.copyFileSync(job.source,source);
 job.local_source=path.relative(root,source);
 if(job.type==='icon'){
  const dir=path.join(root,'icons',job.category);mkdir(dir);
  const files={};
  for(const size of [48,96,256]){
   const dest=path.join(dir,size===48?job.id+'.png':job.id+'_'+size+'.png');
   const inner=Math.round(size*.75);
   magick([source,'-trim','+repage','-filter','point','-resize',inner+'x'+inner,'-gravity','center','-background','none','-extent',size+'x'+size,'-define','png:color-type=6',dest]);
   files[size]=path.relative(root,dest);
  }
  output.push({id:job.id,type:'icon',category:job.category,files,source:job.local_source,anchor:'center',integrated:false});
 } else if(job.type==='monster'){
  const dir=path.join(root,'monsters',job.id);mkdir(dir);
  const size=job.id.startsWith('boss')?192:112;const anchor=job.id.startsWith('boss')?[96,152]:[56,88];
  const concept=path.join(dir,'concept_512.png');
  magick([source,'-trim','+repage','-filter','point','-resize','448x448','-gravity','center','-background','none','-extent','512x512','-define','png:color-type=6',concept]);
  const sprite=path.join(dir,'keypose_'+size+'.png');
  magick([source,'-trim','+repage','-filter','point','-resize',Math.round(size*.86)+'x'+Math.round(size*.65),'-gravity','south','-background','none','-extent',size+'x'+anchor[1],'-gravity','north','-extent',size+'x'+size,'-define','png:color-type=6',sprite]);
  output.push({id:job.id,name:job.name,type:'monster',source:job.local_source,concept:path.relative(root,concept),sprite:path.relative(root,sprite),size:[size,size],anchor,direction:'sw',states:['static_keypose'],full_animation:false,integrated:false});
 } else if(job.type==='fx'){
  const dir=path.join(root,'fx',job.id);const framesDir=path.join(dir,'frames');mkdir(framesDir);
  const [w,h]=magick(['identify','-format','%w %h',source]).trim().split(' ').map(Number);
  const frames=[];const fps=job.id==='spirit_storm'?10:12;
  for(let i=0;i<8;i++){
   const x0=Math.round((i%4)*w/4),x1=Math.round((i%4+1)*w/4),y0=Math.round(Math.floor(i/4)*h/2),y1=Math.round((Math.floor(i/4)+1)*h/2);
   const ix=Math.ceil((x1-x0)*.04),iy=Math.ceil((y1-y0)*.04);
   const dest=path.join(framesDir,String(i).padStart(2,'0')+'.png');
   if(i===7)magick(['-size','128x128','xc:none','-define','png:color-type=6',dest]);
   else magick([source,'-crop',`${x1-x0-2*ix}x${y1-y0-2*iy}+${x0+ix}+${y0+iy}`,'+repage','-filter','point','-resize','118x118!','-gravity','center','-background','none','-extent','128x128','-define','png:color-type=6',dest]);
   frames.push(dest);
  }
  const atlas=path.join(dir,'atlas.png');magick(['montage','-font','/System/Library/Fonts/Supplemental/Arial.ttf',...frames,'-tile','4x2','-geometry','128x128+0+0','-background','none',atlas]);
  const preview=path.join(dir,'preview.gif');magick(['-delay',String(Math.round(100/fps)),'-dispose','background',...frames,'-loop','0',preview]);
  const meta={id:job.id,type:'fx',source:job.local_source,atlas:path.relative(root,atlas),frames:8,frame_size:[128,128],columns:4,rows:2,fps,loop:false,anchor:[64,64],hit_frames:job.id==='spirit_storm'?[1,3,5]:[3],transparent_end:true,preview_loop_only:true,gameplay_callbacks:false,integrated:false};
  fs.writeFileSync(path.join(dir,'animation.json'),JSON.stringify(meta,null,2));output.push(meta);
 }
}
// Deterministic code-native UI frame artwork: exact squares, with uninterrupted transparent interiors.
const qualities=[['uncommon','优秀','#4AA3E0',1],['rare','稀有','#46C46A',2],['epic','史诗','#E0C04A',4],['legendary','传说','#B46AE0',4]];
function perimeter(t){t=((t%1)+1)%1;const n=t*4;if(n<1)return [6+52*n,6];if(n<2)return [58,6+52*(n-1)];if(n<3)return [58-52*(n-2),58];return [6,58-52*(n-3)];}
for(const [id,name,color,ornaments] of qualities){
 const dir=path.join(root,'quality_frames',id);mkdir(path.join(dir,'frames'));mkdir(path.join(dir,'svg'));
 const frames=[],small=[];
 for(let i=0;i<24;i++){
  const pulse=.65+.18*Math.sin(i/24*Math.PI*2);
  let body=`<rect x="6" y="6" width="52" height="52" fill="none" stroke="${color}" stroke-width="6" opacity="${pulse*.12}"/><rect x="6" y="6" width="52" height="52" fill="none" stroke="${color}" stroke-width="3" opacity="${pulse*.30}"/><rect x="6" y="6" width="52" height="52" fill="none" stroke="${color}" stroke-width="1" opacity=".95"/><rect x="8" y="8" width="48" height="48" fill="none" stroke="${color}" stroke-width=".5" opacity=".32"/>`;
  const rotations=[0,180,90,270].slice(0,ornaments);
  for(const angle of rotations)body+=`<g transform="rotate(${angle} 32 32)"><path d="M4 13 V4 H13 M9 4 V9 H4" fill="none" stroke="${color}" stroke-width="1.5"/><rect x="5" y="5" width="2" height="2" fill="#E6DDC6" opacity="${pulse}"/></g>`;
  for(let j=0;j<(id==='legendary'?4:2);j++){
   const offset=j/(id==='legendary'?4:2);const [x,y]=perimeter(i/24+offset);
   for(let k=7;k>=1;k--){const [tx,ty]=perimeter(i/24+offset-k*.008);body+=`<rect x="${tx-.6}" y="${ty-.6}" width="1.2" height="1.2" fill="${color}" opacity="${(8-k)/12}"/>`;}
   body+=`<rect x="${x-1.5}" y="${y-1.5}" width="3" height="3" fill="${color}" opacity=".32"/><rect x="${x-.7}" y="${y-.7}" width="1.4" height="1.4" fill="#F3F5E9"/>`;
   if(j===0)body+=`<path d="M${x-2} ${y} H${x+2} M${x} ${y-2} V${y+2}" fill="none" stroke="#F3F5E9" stroke-width=".8" opacity=".9"/>`;
  }
  if(id==='legendary')body+=`<path d="M29 5 L32 2 L35 5 L32 8 Z M29 59 L32 56 L35 59 L32 62 Z" fill="${color}" stroke="#E6DDC6" stroke-width=".5" opacity="${pulse}"/>`;
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">${body}</svg>`;
  const svgpath=path.join(dir,'svg',String(i).padStart(2,'0')+'.svg');fs.writeFileSync(svgpath,svg);
  const frame=path.join(dir,'frames',String(i).padStart(2,'0')+'.png');magick(['-background','none',svgpath,'-channel','A','-fx','(r+g+b==0)?0:a','+channel','-define','png:color-type=6',frame]);frames.push(frame);
  const f48=path.join(dir,'frames',String(i).padStart(2,'0')+'_48.png');magick([frame,'-filter','point','-resize','48x48','-define','png:color-type=6',f48]);small.push(f48);
 }
 const atlas=path.join(dir,'atlas_64.png');magick(['montage','-font','/System/Library/Fonts/Supplemental/Arial.ttf',...frames,'-tile','6x4','-geometry','64x64+0+0','-background','none',atlas]);
 const atlas48=path.join(dir,'atlas_48.png');magick(['montage','-font','/System/Library/Fonts/Supplemental/Arial.ttf',...small,'-tile','6x4','-geometry','48x48+0+0','-background','none',atlas48]);
 fs.copyFileSync(frames[0],path.join(dir,'static.png'));
 magick(['-delay','8','-dispose','background',...frames,'-loop','0',path.join(dir,'preview.gif')]);
 const meta={id,name,type:'quality_frame',color,atlas:path.relative(root,atlas),atlas48:path.relative(root,atlas48),frames:24,frame_size:[64,64],columns:6,rows:4,fps:12,loop:true,duration_seconds:2,transparent_inner_rect:[12,12,40,40],source:path.relative(root,path.join(dir,'svg')),generator:'deterministic SVG + ImageMagick',integrated:false};
 fs.writeFileSync(path.join(dir,'animation.json'),JSON.stringify(meta,null,2));output.push(meta);
}
const previousManifestPath=path.join(root,'asset_manifest.json');
if(fs.existsSync(previousManifestPath)){
 const previous=JSON.parse(fs.readFileSync(previousManifestPath,'utf8'));
 for(const a of output){const old=previous.assets.find(x=>x.id===a.id&&x.type===a.type);if(a.type==='icon'&&old?.runtime_icon){a.integrated=true;a.runtime_icon=old.runtime_icon;}if(a.type==='monster'&&old?.animation_pack){for(const key of ['full_animation','animation_pack','animation_direction_order','animation_frame_count','states','integrated','runtime_root','runtime_controller'])a[key]=old[key];}}
}
fs.writeFileSync(path.join(root,'asset_manifest.json'),JSON.stringify({created:'2026-10-13',completed:'2026-10-14',integrated:false,image_generator:'built-in image_gen',assets:output},null,2));
fs.writeFileSync(path.join(root,'sources/generation_manifest.json'),JSON.stringify(jobs,null,2));
console.log('Packaged',output.length,'asset entries: 35 icons, 4 monster designs, 6 VFX, 4 quality animations.');
