#!/usr/bin/env python3
"""Bounded local HTTP smoke; no model request, credentials or sandbox bypass."""
from pathlib import Path
import http.cookiejar, json, os, re, resource, signal, subprocess, time, urllib.request

assert os.geteuid()!=0, 'run as boarduser'
report=Path('/home/boarduser/harness-armhf-validation-20261027')
workspace=Path('/home/boarduser/deepseek-harness-armhf/workspace')
workspace.mkdir(exist_ok=True)
command=['/usr/local/bin/dsh-armhf','web','--host','127.0.0.1','--port','3080','--no-open']
result={'command':command,'url':'http://127.0.0.1:3080/','ready':False}
started=time.monotonic()
opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
with (report/'web-startup.log').open('w') as log:
 process=subprocess.Popen(command,cwd=workspace,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 try:
  while time.monotonic()-started<180:
   if process.poll() is not None:
    result['earlyExit']=process.returncode;break
   try:
    text=(report/'web-startup.log').read_text(errors='replace')
    match=re.search(r'http://127\.0\.0\.1:3080/\?token=<redacted>',text)
    requestUrl=match.group(0) if match else result['url']
    with opener.open(requestUrl,timeout=3) as response:
     data=response.read()
     result.update({'status':response.status,'contentType':response.headers.get('Content-Type'),'bytes':len(data),'html':b'<html' in data.lower() or b'<!doctype html' in data.lower()})
     if response.status==200 and result['html']:
      result['ready']=True;result['authenticated']=bool(match)
      result.pop('lastHttpError',None);break
   except Exception as error:result['lastHttpError']=str(error)
   time.sleep(2)
 finally:
  if process.poll() is None:
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=20)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
  result['exitAfterCleanup']=process.returncode
result['elapsedSeconds']=round(time.monotonic()-started,2)
result['maxRssKiB']=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
logPath=report/'web-startup.log'
logPath.write_text(re.sub(r'(\?token=<redacted>&]+',r'\1<redacted>',logPath.read_text(errors='replace')))
(report/'web-startup.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
raise SystemExit(0 if result['ready'] else 1)
