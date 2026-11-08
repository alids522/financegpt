"""Server-authorized bootstrap. Explicit target; never promotes the first signup.
Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Credentials are written only to --output.
"""
import argparse, json, os, pathlib, secrets, urllib.request
parser=argparse.ArgumentParser();parser.add_argument('--username',required=True);parser.add_argument('--email',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
url=os.environ['SUPABASE_URL'];key=os.environ['SUPABASE_SERVICE_ROLE_KEY'];password=secrets.token_urlsafe(32)+'!Aa1'
def call(path,body=None,method='POST',token=key):
 request=urllib.request.Request(url+path,data=None if body is None else json.dumps(body).encode(),method=method,headers={'apikey':key,'Authorization':'Bearer '+token,'Content-Type':'application/json','Content-Profile':'financegpt','Accept-Profile':'financegpt','Prefer':'return=representation'})
 with urllib.request.urlopen(request,timeout=30)as r:return json.loads(r.read()or'{}')
user=call('/auth/v1/admin/users',{'email':args.email,'password':password,'email_confirm':True,'user_metadata':{'app':'financegpt','username':args.username}})
session=call('/auth/v1/token?grant_type=password',{'email':args.email,'password':password})
call('/rest/v1/rpc/initialize_profile',{},token=session['access_token'])
call('/rest/v1/user_roles?user_id=eq.'+user['id'],{'role':'admin'},method='PATCH')
call('/rest/v1/profiles?user_id=eq.'+user['id'],{'must_change_password':True},method='PATCH')
output=pathlib.Path(args.output);output.write_text(json.dumps({'username':args.username,'email':args.email,'temporary_password':password,'must_change_password':True},indent=2));output.chmod(0o600)
print('Created explicit administrator; credentials saved to the requested local file.')
