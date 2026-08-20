function required(value,label){if(value===undefined||value===null||String(value)==='')throw new Error(`${label} is required`);return String(value);}

function hash32(value,seed){
  let hash=(0x811c9dc5^seed)>>>0;
  for(const character of String(value)){hash^=character.charCodeAt(0);hash=Math.imul(hash,0x01000193)>>>0;}
  return hash>>>0;
}

function deterministicUuid(value){
  const hex=[0,1,2,3].map(seed=>hash32(value,seed*0x9e3779b1).toString(16).padStart(8,'0')).join('').split('');
  hex[12]='4';hex[16]=((parseInt(hex[16],16)&3)|8).toString(16);
  const joined=hex.join('');
  return `${joined.slice(0,8)}-${joined.slice(8,12)}-${joined.slice(12,16)}-${joined.slice(16,20)}-${joined.slice(20)}`;
}

function routePath(route,context){
  const raceId=()=>encodeURIComponent(required(context.raceId,'raceId'));
  switch(route.requestBuilder){
    case 'race_messages':return `/races/${raceId()}/messages?limit=50`;
    case 'challenges_current':return '/challenges/current';
    case 'assets_manifest':return '/assets/manifest';
    case 'race_resolution':return `/steps/race-resolution/${encodeURIComponent(required(context.resolutionJob?.jobId,'resolutionJob.jobId'))}?generation=${Number(context.resolutionJob?.generation||1)}`;
    case 'steps_post':return '/steps';
    case 'races_list':return '/races?view=compact-v1';
    case 'steps_samples':return '/steps/samples';
    case 'race_progress':return `/races/${raceId()}/progress?view=participants-v1&offset=0&limit=15`;
    case 'auth_me':return '/auth/me';
    case 'steps_sync_v2':return '/steps/sync-v2';
    case 'home_race_card':return `/home/race-card?view=shell-v1&homeActiveRaces=1&localDate=${encodeURIComponent(required(context.localDate,'localDate'))}`;
    case 'suggested_races':return '/home/suggested-races';
    case 'powerups_inventory':return '/powerups/inventory';
    case 'app_version_policy':return '/app-version/policy';
    case 'race_message_streams':return `/races/${raceId()}/message-streams?view=conditional-v1&includeUser=true&limit=50`;
    case 'friends_steps':return `/friends/steps?date=${encodeURIComponent(required(context.localDate,'localDate'))}`;
    case 'powerups_catalog':return '/powerups/catalog';
    case 'shop_catalog':return '/shop/catalog';
    case 'analytics_activation_events':return '/analytics/activation-events';
    case 'races_discovery_summary':return '/races/discovery-summary';
    case 'races_invite_preflight':return '/races/invite-preflight';
    case 'race_chat_read':return `/races/${raceId()}/chat/read`;
    case 'notification_device_token':return '/notifications/device-token';
    case 'auth_session':return '/auth/session';
    case 'friends_list':return '/friends';
    case 'onboarding_starter_reward':return '/onboarding/starter-reward';
    case 'race_bootstrap':return `/races/${raceId()}/bootstrap?view=compact-v1`;
    case 'race_detail':return `/races/${raceId()}?view=compact-v1`;
    case 'leaderboard':return '/leaderboard?type=steps&period=today&scope=global';
    case 'daily_reward_status':return `/daily-reward/status?localDate=${encodeURIComponent(required(context.localDate,'localDate'))}&view=get-coins-v1`;
    case 'step_milestones_today':return `/users/me/step-milestones/today?localDate=${encodeURIComponent(required(context.localDate,'localDate'))}`;
    case 'web_asset':return '/web-assets/capybara.png';
    case 'root_web':return '/';
    default:throw new Error(`no request builder for ${route.requestBuilder}`);
  }
}

export function buildRegisteredRequest(route,context){
  if(!Array.isArray(route.acceptedStatuses)||!['GET','POST'].includes(route.method))throw new Error(`invalid registry route ${route.key}`);
  const headers={
    'X-Timezone':context.client.timezone,
    'X-Release-Channel':context.client.releaseChannel,
    'X-App-Version':context.client.appVersion,
    'X-Platform':context.client.platform,
    'X-Client-Features':context.client.clientFeatures,
    'User-Agent':context.client.userAgent,
    'X-Capacity-Run-Id':context.runId,
    'X-Capacity-Repeat':String(context.repeat),
  };
  if(route.persona!=='anonymous')headers.Authorization=`Bearer ${required(context.user?.token,'user token')}`;
  if(route.method==='POST')headers['Content-Type']='application/json';
  if(route.requestBuilder==='steps_sync_v2')headers['Idempotency-Key']=deterministicUuid(`${context.runId}:${context.repeat}:${context.phase}:${context.writeOrdinal}`);
  return {method:route.method,url:`${context.baseUrl}${routePath(route,context)}`,body:null,acceptedStatuses:route.acceptedStatuses,params:{headers,timeout:'15s',redirects:0,tags:{phase:context.phase,endpoint:route.key}}};
}
