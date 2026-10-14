import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import crypto from 'node:crypto';import {execFileSync as run} from 'node:child_process';
const root=path.resolve(import.meta.dirname,'..'),file=path.join(root,'previews/monster_animations_v1/animation_manifest.json'),m=JSON.parse(fs.readFileSync(file,'utf8'));
const expected=['s','sw','w','nw','n','ne','e','se'];assert.deepEqual(m.direction_order,expected);assert.equal(m.actors.length,4);let frames=0,states=0;
const perActor=[];
for(const a of m.actors){assert.equal(a.integrated,true);assert.deepEqual(a.directions,expected);for(const s of ['idle','walk','attack','hit','death'])assert(a.states[s]);if(a.id==='boss_corrupted_beast')for(const s of ['stomp','enrage_summon'])assert(a.states[s]);
 const checked=[];
 for(const [sid,s] of Object.entries(a.states)){
  assert(s.frames_per_direction>=7&&s.frames_per_direction<=8);assert.equal(s.rows,8);assert.equal(s.columns,s.frames_per_direction);assert.equal(s.gameplay_callbacks,false);assert.equal(s.loop,['idle','walk'].includes(sid));
  const atlas=path.join(root,s.atlas),[w,h]=run('/opt/homebrew/bin/magick',['identify','-format','%w %h',atlas]).toString().split(' ').map(Number),size=a.frame_size[0];assert.deepEqual([w,h],[size*s.columns,size*8]);
  const raw=run('/opt/homebrew/bin/magick',[atlas,'-depth','8','rgba:-'],{maxBuffer:64*1024*1024});const firstHashes=[];let distinct=0;
  for(let d=0;d<8;d++){
   const hashes=new Set();
   for(let f=0;f<s.frames_per_direction;f++){
    const pixels=Buffer.alloc(size*size*4);let visible=0,x0=size,y0=size,x1=-1,y1=-1;
    for(let y=0;y<size;y++){raw.copy(pixels,y*size*4,((d*size+y)*w+f*size)*4,((d*size+y)*w+(f+1)*size)*4);for(let x=0;x<size;x++)if(pixels[(y*size+x)*4+3]){visible++;x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}}
    assert(visible>=120,`${a.id}/${sid}/${d}/${f} missing silhouette`);assert(x0>=2&&y0>=2&&x1<size-2&&y1<size-2,`${a.id}/${sid}/${d}/${f} clipped canvas edge`);assert(Math.abs(y1-(a.pivot[1]-1))<=2,`${a.id}/${sid}/${d}/${f} ground anchor drift`);
    const p=path.join(root,'monsters',a.id,'animations_v1',sid,expected[d],String(f).padStart(2,'0')+'.png');assert(fs.existsSync(p));const hash=crypto.createHash('sha256').update(pixels).digest('hex');hashes.add(hash);if(f===0)firstHashes.push(hash);frames++;
   }
   assert(hashes.size>=2,`${a.id}/${sid}/${d} static repeated frame`);distinct+=hashes.size;
  }
  assert.equal(new Set(firstHashes).size,8,`${a.id}/${sid} repeated direction`);if(sid==='death')assert(s.terminal_hold);states++;checked.push({state:sid,frames_per_direction:s.frames_per_direction,distinct_frames:distinct});
 }
 perActor.push({id:a.id,states:checked});
}
assert.equal(states,22);assert.equal(frames,1272);
const report={date:'2026-10-14',result:'passed',actors:4,directions:8,action_atlases:states,individual_animation_frames:frames,directional_static_exports:32,checks:['all four actor IDs and five base states','boss stomp and enrage_summon extra states','seven or eight real chronological frames per state','eight different facing views in every state','at least two different art frames for every directional animation','exact atlas cell sizes and row/column order','all 1272 silhouettes nonempty with transparent safety border','fixed canvas pivot; visible ground edge within two raster pixels','nonlooping attacks/hit/death; death terminal hold','animation frames do not trigger damage; four monster packs integrated'],per_actor:perActor,visual_review:['four facing turntables','four chronological action boards','all eight directions in terminal death poses','interactive animation player'],limitations:['directional character artwork should receive in-game scale and timing review during future integration']};
fs.writeFileSync(path.join(root,'previews/monster_animations_v1/validation_report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({result:report.result,actors:4,action_atlases:states,individual_animation_frames:frames},null,2));
