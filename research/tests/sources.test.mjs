import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sourceConfig,planQueries,topicMatch,normalizeEvidence,collectSources} from '../sources.mjs';

const profile={
 clusters:[
  {id:'manager_bottleneck',terms_he:['צוואר בקבוק ניהולי'],terms_en:['manager bottleneck','review bottleneck']},
  {id:'leadership_delegation',terms_he:['האצלת סמכויות'],terms_en:['engineering leadership','delegation']},
  {id:'ownership_execution',terms_he:['בעלות על תוצאה'],terms_en:['decision ownership','delivery predictability']},
  {id:'ai_management',terms_he:['ניהול בעידן AI'],terms_en:['AI engineering management']},
  {id:'ai_code_factory',terms_he:['מפעל קוד'],terms_en:['AI code factory','coding agents']},
 ],
 managerial_terms_he:['מנהל','ניהולי','צוות','האצלת סמכויות'],
 managerial_terms_en:['engineering manager','manager','leadership','delegation','review bottleneck','decision ownership'],
};
const env={CMK_RESEARCH_NETWORK_ENABLED:'true',CMK_RESEARCH_PAID_CALLS_ENABLED:'true',
 CMK_RESEARCH_PROVIDER:'brave',CMK_RESEARCH_API_KEY:'RESEARCH-TEST-SECRET'};
const fetchedAt='2026-11-04T10:00:00.000Z';
const query={id:'q-1',cluster_id:'manager_bottleneck',query:'"review bottleneck" "engineering manager"',language:'en',platform:'linkedin'};
const imported={url:'https://www.linkedin.com/posts/test-review-bottleneck-123',
 title:'Engineering managers and the review bottleneck',text:'Coding agents create a review bottleneck for engineering managers.',
 content_kind:'imported_excerpt',public:true,published_at:'2026-11-03T09:00:00.000Z'};
const raw={url:imported.url,title:imported.title,description:imported.text,page_age:'2026-11-03T09:00:00.000Z'};

function options(extra={}) {
 return {query,provider:'brave',fetchedAt,profile,...extra};
}

test('source search needs its own explicit access and payment gates; LLM payment never authorizes it',()=>{
 assert.equal(sourceConfig().enabled,false);
 assert.equal(sourceConfig(env,false).enabled,false);
 assert.equal(sourceConfig({CMK_LLM_PAID_CALLS_ENABLED:'true',CMK_LLM_API_KEY:'key'},true).enabled,false);
 assert.equal(sourceConfig({...env,CMK_RESEARCH_NETWORK_ENABLED:'false'},true).enabled,false);
 assert.equal(sourceConfig({...env,CMK_RESEARCH_PAID_CALLS_ENABLED:'false'},true).enabled,false);
 assert.equal(sourceConfig(env,true).enabled,true);
});

test('enabled search requires a supported provider, credentials and valid limits',()=>{
 assert.throws(()=>sourceConfig({...env,CMK_RESEARCH_PROVIDER:'unreviewed-provider'},true));
 assert.throws(()=>sourceConfig({...env,CMK_RESEARCH_API_KEY:''},true));
 assert.throws(()=>sourceConfig({...env,CMK_RESEARCH_TIMEOUT_MS:'-1'},true));
});

test('query plan is bounded, reproducible and tied to profile clusters in Hebrew and English',()=>{
 const plan=planQueries(profile,{maxQueries:8});
 assert.ok(plan.length>0&&plan.length<=8);assert.deepEqual(plan,planQueries(profile,{maxQueries:8}));
 assert.equal(new Set(plan.map(q=>q.query)).size,plan.length);
 assert.ok(plan.some(q=>q.language==='he'));assert.ok(plan.some(q=>q.language==='en'));
 for(const q of plan){assert.ok(profile.clusters.some(c=>c.id===q.cluster_id));assert.ok(q.query.trim().length>8);}
});

test('topic matching accepts concrete The Push problems and excludes generic AI news',()=>{
 assert.equal(topicMatch({title:imported.title,text:imported.text},profile).relevant,true);
 assert.equal(topicMatch({title:'צוואר בקבוק ניהולי',text:'מנהל צוות צריך האצלת סמכויות'},profile).relevant,true);
 assert.equal(topicMatch({title:'AI code factory',text:'AI code factory raises decision ownership issues for engineering managers'},profile).relevant,true);
 assert.equal(topicMatch({title:'A new AI image generator launched',text:'More beautiful vacation photos in seconds'},profile).relevant,false);
 assert.equal(topicMatch({title:'Summer holidays',text:'Travel booking tips'},profile).relevant,false);
});

test('provider snippets retain provenance and never masquerade as full posts or dated publications',()=>{
 const e=normalizeEvidence({...raw,metrics:{comments:10000},published_at:'2026-11-01T00:00:00Z'},options());
 assert.equal(e.content_kind,'search_snippet');assert.equal(e.provider,'brave');assert.equal(e.platform,'linkedin');
 assert.equal(e.url,raw.url);assert.equal(e.fetched_at,fetchedAt);assert.equal(e.published_at,null);
 assert.ok(e.page_date);assert.equal(e.page_date_basis,'provider_published_or_modified');
 assert.equal(e.metrics.comments,null);assert.equal(e.metrics.reactions,null);assert.equal(e.metrics.impressions,null);
 assert.match(JSON.stringify(e.limitations),/snippet/i);
});

test('unknown source dates stay null and retrieval time is not substituted for publication date',()=>{
 const e=normalizeEvidence({...raw,page_age:undefined},options());
 assert.equal(e.published_at,null);assert.equal(e.page_date,null);assert.equal(e.fetched_at,fetchedAt);
});

test('imported excerpts require public source confirmation and retain explicit publication dates',()=>{
 assert.throws(()=>normalizeEvidence({...imported,public:false},options({provider:'import',imported:true})));
 const e=normalizeEvidence(imported,options({provider:'import',imported:true}));
 assert.equal(e.content_kind,'imported_excerpt');assert.equal(e.published_at,imported.published_at);
 assert.equal(e.metrics.comments,null);assert.equal(e.metrics_source,null);
});

test('engagement counts require independent source/time provenance; zero is retained as an observation',()=>{
 const noProof=normalizeEvidence({...imported,metrics:{comments:9999}},options({provider:'import',imported:true}));
 assert.equal(noProof.metrics.comments,null);
 const e=normalizeEvidence({...imported,metrics:{comments:0,reactions:12},metrics_observed_at:fetchedAt,
 metrics_source:{url:imported.url,kind:'manual_observation'}},options({provider:'import',imported:true}));
 assert.equal(e.metrics.comments,0);assert.equal(e.metrics.reactions,12);assert.equal(e.metrics.impressions,null);
 assert.equal(e.metrics_observed_at,fetchedAt);assert.ok(e.metrics_source);
});

test('profile, login and private URLs are not accepted as public discussion evidence',()=>{
 for(const url of ['https://www.linkedin.com/in/example','https://www.linkedin.com/login',
 'https://www.reddit.com/login','https://x.com/example'])
 assert.throws(()=>normalizeEvidence({...imported,url},options({provider:'import',imported:true})));
});

test('offline research performs no transport requests and can use documented imports',async()=>{
 let calls=0;
 const r=await collectSources(profile,{imported:[imported],fetchImpl:async()=>{calls++;throw Error('must not fetch');},now:()=>fetchedAt});
 assert.equal(calls,0);assert.equal(r.external_calls,0);assert.equal(r.evidence.length,1);
 assert.equal(r.evidence[0].metrics.comments,null);assert.ok(r.coverage);
});

test('irrelevant imports are rejected rather than padding focused research coverage',async()=>{
 const r=await collectSources(profile,{imported:[{...imported,title:'Travel inspiration',text:'Beautiful beaches and summer deals'}],now:()=>fetchedAt});
 assert.equal(r.evidence.length,0);assert.ok(r.rejected.length>0);
});

test('online search refuses unaccounted transport calls',async()=>{
 let calls=0;
 await assert.rejects(collectSources(profile,{cfg:sourceConfig(env,true),queries:[query],fetchImpl:async()=>{calls++;return new Response('{}');}}));
 assert.equal(calls,0);
});

test('reservation hook runs before transport and completion audit runs afterward',async()=>{
 const events=[];
 const r=await collectSources(profile,{cfg:sourceConfig(env,true),queries:[query],now:()=>fetchedAt,
 beforeRequest:async()=>{events.push('reserve');return {id:'reservation-1'};},
 fetchImpl:async(url,opt)=>{events.push('fetch');assert.ok(String(url).startsWith('https://api.search.brave.com/'));
  assert.equal(opt.redirect,'error');return new Response(JSON.stringify({web:{results:[raw]}}),{status:200});},
 afterRequest:async result=>{events.push('audit');assert.equal(result.token.id,'reservation-1');assert.equal(result.status,'succeeded');}});
 assert.deepEqual(events,['reserve','fetch','audit']);assert.equal(r.external_calls,1);assert.equal(r.evidence.length,1);
 assert.equal(r.evidence[0].content_kind,'search_snippet');assert.equal(r.evidence[0].metrics.comments,null);
});

test('budget reservation denial stops all queries before network access',async()=>{
 let calls=0;
 const r=await collectSources(profile,{cfg:sourceConfig(env,true),queries:[query,{...query,id:'q-2',query:'delegation'}],
 beforeRequest:async()=>{throw Error('research_budget_exceeded');},afterRequest:async()=>{},
 fetchImpl:async()=>{calls++;return new Response('{}');},now:()=>fetchedAt});
 assert.equal(calls,0);assert.equal(r.external_calls,0);assert.ok(r.coverage);
});

test('unknown transport is audited without leaking provider keys or fabricating evidence',async()=>{
 let audited;
 const r=await collectSources(profile,{cfg:sourceConfig(env,true),queries:[query],now:()=>fetchedAt,
 beforeRequest:async()=>({id:'unknown'}),afterRequest:async result=>{audited=result;},
 fetchImpl:async()=>{throw Error(env.CMK_RESEARCH_API_KEY);}});
 assert.equal(audited.status,'unknown');assert.equal(r.evidence.length,0);
 assert.ok(!JSON.stringify(r).includes(env.CMK_RESEARCH_API_KEY));assert.ok(!JSON.stringify(audited).includes(env.CMK_RESEARCH_API_KEY));
});

test('only a supplied full post can provide an observed opening; snippets and excerpts cannot',()=>{
 const snippet=normalizeEvidence(raw,options());assert.equal(snippet.hook_candidate,null);
 const excerpt=normalizeEvidence(imported,options({provider:'import',imported:true}));assert.equal(excerpt.hook_candidate,null);
 const full=normalizeEvidence({...imported,content_kind:'full_post',text:'Who owns the review bottleneck?\n\nCoding agents keep engineering managers in every review.'},options({provider:'import',imported:true}));
 assert.equal(full.hook_candidate,'Who owns the review bottleneck?');assert.equal(full.hook_candidate_basis,'imported_full_post_first_line');
});

test('tracking-link duplicates do not inflate the count of independent sources',async()=>{
 const r=await collectSources(profile,{imported:[imported,{...imported,url:imported.url+'?utm_source=duplicate&utm_campaign=test'}],now:()=>fetchedAt});
 assert.equal(r.evidence.length,1);assert.equal(r.evidence[0].url,imported.url);
});

test('invalid imported metric counts with claimed provenance are rejected, not coerced or inferred',()=>{
 for(const value of [-1,3.5,'100'])
 assert.throws(()=>normalizeEvidence({...imported,metrics:{comments:value},metrics_observed_at:fetchedAt,
 metrics_source:{url:imported.url,kind:'manual_observation'}},options({provider:'import',imported:true})),/invalid_metric/);
});
