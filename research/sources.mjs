// Public source discovery, not a signed-in social scraper. Business topics come from Postgres.
import {createHash} from 'node:crypto';

const ENDPOINT='https://api.search.brave.com/res/v1/web/search';
const METRICS=['impressions','reactions','comments','shares'];
const GENERIC_TERMS=new Set(['ai','management','leadership','code','software','the push','ניהול','מנהיגות']);
const SITES={linkedin:'site:linkedin.com/posts/ OR site:linkedin.com/pulse/ OR site:linkedin.com/feed/update/',reddit:'site:reddit.com/r/',x:'site:x.com OR site:twitter.com'};
const bodyOf=p=>p?.body||p;
const list=v=>Array.isArray(v)?v:[];
const norm=s=>String(s||'').normalize('NFKC').toLowerCase().replace(/[\p{P}\p{S}]+/gu,' ').replace(/\s+/g,' ').trim();
const clean=s=>String(s||'').replace(/<[^>]*>/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/\s+/g,' ').trim();
const bounded=(n,fallback,max)=>Number.isSafeInteger(Number(n))&&Number(n)>0?Math.min(Number(n),max):fallback;
function date(value) {
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))?$/.test(value)||Number.isNaN(Date.parse(value)))return null;
 return value.length===10?value:new Date(value).toISOString();
}
function termMatch(text,term) {
 const t=norm(term);if(!t||GENERIC_TERMS.has(t))return false;
 return (' '+text+' ').includes(' '+t+' ')||(/^[a-z]+$/.test(t)&&(' '+text+' ').includes(' '+t+'s '));
}
function canonicalURL(value) {
 const url=new URL(value);
 if(url.protocol!=='https:'||url.username||url.password||!url.hostname.includes('.')||url.hostname.includes(':')||/^\d+(?:\.\d+){3}$/.test(url.hostname)||/\.(?:localhost|local|internal)$/.test(url.hostname))throw Error('research_source:public_https_url_required');
 url.hash='';
 for(const k of [...url.searchParams.keys()])if(/^utm_/i.test(k)||['fbclid','gclid','li_fat_id','trk','trackingId'].includes(k))url.searchParams.delete(k);
 const host=url.hostname.replace(/^www\./,'');
 if(host==='linkedin.com'&&!/^\/(?:posts\/|pulse\/|feed\/update\/)/.test(url.pathname))throw Error('research_source:public_linkedin_post_required');
 if(['x.com','twitter.com'].includes(host)&&!/^\/[^/]+\/status\//.test(url.pathname))throw Error('research_source:public_x_post_required');
 if(host.endsWith('reddit.com')&&!/\/comments\//.test(url.pathname))throw Error('research_source:public_reddit_discussion_required');
 return url.href;
}
function platform(url) {
 const host=new URL(url).hostname.replace(/^www\./,'');
 if(host==='linkedin.com')return 'linkedin';
 if(host==='x.com'||host==='twitter.com')return 'x';
 if(host==='reddit.com'||host.endsWith('.reddit.com'))return 'reddit';
 return 'web';
}
export function sourceConfig(env=process.env,allowNetwork=false) {
 if(allowNetwork!==true||env.CMK_RESEARCH_NETWORK_ENABLED!=='true'||env.CMK_RESEARCH_PAID_CALLS_ENABLED!=='true')return {enabled:false};
 if(env.CMK_RESEARCH_PROVIDER!=='brave'||!env.CMK_RESEARCH_API_KEY?.trim())throw Error('research_config:brave_provider_and_key_required');
 const timeout=env.CMK_RESEARCH_TIMEOUT_MS===undefined?15000:Number(env.CMK_RESEARCH_TIMEOUT_MS);
 if(!Number.isSafeInteger(timeout)||timeout<=0||timeout>60000)throw Error('research_config:valid_timeout_required');
 return {enabled:true,provider:'brave',apiKey:env.CMK_RESEARCH_API_KEY,timeout};
}

export function planQueries(profile,{maxQueries}={}) {
 const p=bodyOf(profile)||{},languages=list(p.languages).length?p.languages:['he','en'];
 const platforms=list(p.platforms).filter(s=>SITES[s]);
 if(!platforms.length)platforms.push('linkedin');
 const max=bounded(maxQueries??p.max_queries,12,50),pairs=list(p.query_pairs).length?p.query_pairs:list(p.clusters);
 const queries=[];
 // Round robin across topics/languages before adding secondary platforms.
 for(const site of platforms)for(const pair of pairs)for(const language of languages) {
  if(!['he','en'].includes(language))continue;
  const terms=list(pair['terms_'+language]).length?pair['terms_'+language]:list(pair['keywords_'+language]);
  const selected=terms.map(t=>String(t).trim()).filter(Boolean).slice(0,2);
  if(!selected.length)continue;
  const q=selected.map(t=>'"'+t.replaceAll('"','')+'"').join(' ')+' ('+SITES[site]+')';
  queries.push({id:`${pair.id||'topic'}:${language}:${site}`,cluster_id:pair.cluster_id||pair.id||null,query:q,language,platform:site});
  if(queries.length>=max)return queries;
 }
 return queries;
}

export function topicMatch(record,profile) {
 const p=bodyOf(profile)||{},text=norm((record.title||'')+' '+(record.text||record.description||''));
 const clusters=[];const terms=[];
 for(const c of list(p.clusters)) {
  const hits=[...list(c.keywords_he),...list(c.keywords_en),...list(c.terms_he),...list(c.terms_en)].filter(t=>termMatch(text,t));
  if(hits.length){clusters.push(c.id);terms.push(...hits);}
 }
 const managerial=[...list(p.managerial_terms_he),...list(p.managerial_terms_en),
  'manager','engineering','engineers','developers','team lead','decision bottleneck','review bottleneck',
  'מנהל','מנהלי','מנהלים','פיתוח','צוואר בקבוק','האצלת סמכויות'].filter(t=>termMatch(text,t));
 // Configured specific topic phrases qualify; bare AI/management never do.
 const excluded=list(p.exclusion_terms).filter(t=>termMatch(text,t));
 const specificFactory=terms.some(t=>['ai code factory','software factory','מפעל קוד'].includes(norm(t)));
 const ambiguous=new Set(['ownership','accountability','execution','delegation','ניהול זמן','ai agents','סוכני ai']);
 const hasSpecific=terms.some(t=>!ambiguous.has(norm(t))&&norm(t).split(' ').length>1);
 return {relevant:clusters.length>0&&excluded.length===0&&(managerial.length>0||specificFactory||hasSpecific),cluster_ids:[...new Set(clusters)],matched_terms:[...new Set(terms)],managerial_terms:[...new Set(managerial)],excluded_terms:excluded,
  basis:'deterministic_keyword_match_not_semantic_validation'};
}

export function normalizeEvidence(raw,{query=null,provider='import',fetchedAt=new Date().toISOString(),profile,imported=false}={}) {
 if(!raw||typeof raw!=='object')throw Error('research_source:object_required');
 const url=canonicalURL(raw.url);
 if(imported&&raw.public!==true)throw Error('research_source:explicit_public_import_required');
 const fetched=date(fetchedAt);if(!fetched)throw Error('research_source:valid_collection_time_required');
 const text=imported?String(raw.text||'').trim():clean(raw.description||raw.snippet||'');
 if(!text)throw Error('research_source:text_or_snippet_required');
 if(text.length>30000)throw Error('research_source:text_too_large');
 const kind=imported?(raw.content_kind==='full_post'?'full_post':'imported_excerpt'):'search_snippet';
 const limitations=imported?['Imported text; not independently fetched. fetched_at is ingestion time.']:['Search snippet, not full post text.','Search indexing is incomplete; results are not a representative social sample.'];
 const metrics=Object.fromEntries(METRICS.map(k=>[k,null]));let metricsSource=null,metricsAt=null;
 if(imported&&raw.metrics) {
  let source=null;
  try {
   if(['public_platform_observation','manual_observation','platform_export'].includes(raw.metrics_source?.kind))source={kind:raw.metrics_source.kind,url:canonicalURL(raw.metrics_source.url)};
  }catch{}
  const at=date(raw.metrics_observed_at);
  if(source&&at) {
   for(const k of METRICS)if(raw.metrics[k]!==undefined&&raw.metrics[k]!==null) {
    if(!Number.isSafeInteger(raw.metrics[k])||raw.metrics[k]<0)throw Error('research_source:invalid_metric');
    metrics[k]=raw.metrics[k];
   }
   metricsSource=source;metricsAt=at;
  }else limitations.push('Imported metrics omitted: observation time and source provenance are required.');
 }
 if(!Object.values(metrics).some(v=>v!==null))limitations.push('No observed engagement metrics; effectiveness is unverified.');
 const pageDate=imported?null:date(raw.page_age);
 const published=imported?date(raw.published_at):null;
 if(!published)limitations.push('Publication date is unverified; collection time is not publication time.');
 const record={id:'source_'+createHash('sha256').update(url).digest('hex'),url,platform:platform(url),title:clean(raw.title).slice(0,500),text,content_kind:kind,
  published_at:published,page_date:pageDate,page_date_basis:pageDate?'provider_published_or_modified':null,fetched_at:fetched,
  query:typeof query==='string'?query:query?.query||null,query_id:typeof query==='object'?query?.id||null:null,provider,
  retrieval_method:imported?'import':'search_api',metrics,metrics_observed_at:metricsAt,metrics_source:metricsSource,
  hook_candidate:kind==='full_post'?text.split(/\r?\n/).find(line=>line.trim())?.trim()||null:null,
  hook_candidate_basis:kind==='full_post'?'imported_full_post_first_line':null,
  source_kind:['linkedin','reddit','x'].includes(platform(url))?'public_discussion':'public_page',limitations};
 record.topic_match=topicMatch(record,profile);
 return record;
}

async function readJSON(response) {
 const reader=response.body?.getReader();if(!reader)throw Error('research_invalid_response');
 const chunks=[];let bytes=0;
 while(true){const r=await reader.read();if(r.done)break;bytes+=r.value.length;if(bytes>2*1024*1024){await reader.cancel();throw Error('research_response_limit');}chunks.push(Buffer.from(r.value));}
 return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export async function collectSources(profile,{cfg={enabled:false},fetchImpl=globalThis.fetch,imported=[],queries,beforeRequest,afterRequest,now=()=>new Date()}={}) {
 const p=bodyOf(profile)||{},planned=queries||planQueries(p),coverage=[],rejected=[],evidence=[],seen=new Set();let externalCalls=0;
 const add=(raw,options)=>{
  try {
   const r=normalizeEvidence(raw,{...options,profile:p,fetchedAt:new Date(now()).toISOString()});
   if(!r.topic_match.relevant){rejected.push({url:r.url,reason:'outside_configured_topics'});return;}
   if(!seen.has(r.id)){seen.add(r.id);evidence.push(r);}
  }catch(e){rejected.push({url:typeof raw?.url==='string'?raw.url:null,reason:e.message});}
 };
 for(const raw of imported) add(raw,{provider:'import',imported:true,query:raw.query||null});
 if(!cfg.enabled)coverage.push({status:'offline',reason:'Network search disabled; imported evidence only.',external_calls:0});
 else {
  if(cfg.provider!=='brave'||!cfg.apiKey||typeof beforeRequest!=='function'||typeof afterRequest!=='function')throw Error('research_config:provider_key_and_durable_hooks_required');
  const count=bounded(p.max_results_per_query,10,20),days=bounded(p.recency_days,30,365);
  const end=new Date(now()),start=new Date(end);start.setUTCDate(start.getUTCDate()-days);
  const freshness=start.toISOString().slice(0,10)+'to'+end.toISOString().slice(0,10);
  for(const q of planned.slice(0,bounded(p.max_queries,12,50))) {
   let token;
   try{token=await beforeRequest({query:q,provider:'brave',request_count:1});}
   catch {coverage.push({query_id:q.id,status:'blocked',reason:'search_reservation_blocked',external_calls:0});break;}
   let status='unknown',errorCode='research_transport_unknown',results=[];
   const endpoint=new URL(ENDPOINT);endpoint.searchParams.set('q',q.query);endpoint.searchParams.set('count',String(count));endpoint.searchParams.set('freshness',freshness);endpoint.searchParams.set('text_decorations','false');
   externalCalls++;
   try {
    const response=await fetchImpl(endpoint.href,{method:'GET',redirect:'error',signal:AbortSignal.timeout(cfg.timeout||15000),headers:{Accept:'application/json','X-Subscription-Token':cfg.apiKey}});
    if(!response.ok){status='failed';errorCode='research_http_'+response.status;}
    else {
     status='failed';errorCode='research_invalid_response';const data=await readJSON(response);
     if(!data.web||!Array.isArray(data.web.results))throw Error(errorCode);
     results=data.web.results.slice(0,count);status='succeeded';errorCode=null;
    }
   }catch { /* Safe status/code only: no provider error or token is logged. */ }
   await afterRequest({token,status,request_count:1,error_code:errorCode});
   coverage.push({query_id:q.id,status,error_code:errorCode,external_calls:1,result_count:results.length,
    requested_window:{from:start.toISOString().slice(0,10),to:end.toISOString().slice(0,10),basis:'provider_page_published_or_modified_date'},
    limitation:'Public search index only; no signed-in or complete platform coverage.'});
   for(const raw of results)add(raw,{provider:'brave',query:q});
   if(status==='unknown')break; // Ambiguous calls are never automatically retried.
  }
 }
 const maxSources=bounded(p.max_sources,30,200);
 if(evidence.length>maxSources)coverage.push({status:'limited',reason:'max_sources',omitted:evidence.length-maxSources});
 const selected=evidence.slice(0,maxSources);
 if(!selected.length)coverage.push({status:'insufficient_evidence',reason:'No accessible in-scope evidence; do not invent a report.'});
 return {evidence:selected,coverage,queries:planned,rejected,external_calls:externalCalls};
}
