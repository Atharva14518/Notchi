#!/usr/bin/env python3
"""Exercise the migration in an isolated, temporary local Postgres cluster."""
import concurrent.futures, json, pathlib, shutil, subprocess, tempfile
base=pathlib.Path(__file__).resolve().parent
root=pathlib.Path(tempfile.mkdtemp(prefix='notchi-links-pg-'))
data=root/'data'; port='26435'
started=False

def run(args, sql=None):
    result=subprocess.run(args,input=sql,text=True,capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()
def query(sql): return run(['psql','-X','-h',str(root),'-p',port,'-d','postgres','-v','ON_ERROR_STOP=1','-At'],sql)
try:
    run(['initdb','-D',str(data),'-A','trust','--no-locale','-E','UTF8'])
    run(['pg_ctl','-D',str(data),'-l',str(root/'postgres.log'),'-o',f"-k {root} -p {port} -c listen_addresses=",'-w','start']);started=True
    query('create role anon;create role authenticated;create role service_role;create schema auth;create table auth.users(id uuid primary key);')
    query((base/'supabase/migrations/202611050001_links.sql').read_text())
    owner='11111111-1111-4111-8111-111111111111';other='22222222-2222-4222-8222-222222222222'
    query(f"insert into auth.users values('{owner}'),('{other}');")
    def reserve(i,who=owner,size=100):
        id=f'00000000-0000-4000-8000-{i:012d}'
        return json.loads(query(f"select link_reserve_upload('{who}','{id}','test.pdf',{size},'application/pdf',now()+interval '30 minutes',1000000000,50);"))
    items=[reserve(i) for i in range(1,6)]
    try: reserve(6);raise AssertionError('sixth free upload succeeded')
    except RuntimeError as error: assert 'quota_exceeded' in str(error)
    try: reserve(7,other,100000001);raise AssertionError('size cap bypassed')
    except RuntimeError as error: assert 'too_large' in str(error)
    query(f"insert into link_accounts values('{other}','paid');")
    assert reserve(8,other,100000001)['size']==100000001
    id=items[0]['id'];slug='a'*24
    query(f"select link_claim_upload('{owner}','{id}');select link_complete_upload('{owner}','{id}','{slug}',now()+interval '1 hour',null,2);")
    tickets=[f'90000000-0000-4000-8000-{i:012d}' for i in range(8)]
    for ticket in tickets:
        assert query(f"select link_issue_ticket('{slug}','{ticket}',now()+interval '30 seconds');")=='t'
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results=list(pool.map(lambda ticket:query(f"select coalesce(link_consume_ticket('{ticket}')::text,'NULL');"),tickets))
    assert query(f"select coalesce(link_consume_ticket('{tickets[0]}')::text,'NULL');")=='NULL', 'ticket replay succeeded'
    assert sum(x!='NULL' for x in results)==2,'concurrent download cap bypassed'
    assert query(f"select coalesce(link_owned_share('{other}','{id}')::text,'NULL');")=='NULL'
    query(f"update link_shares set expires_at=now() where upload_id='{id}';")
    assert query(f"select coalesce(link_claim_download('{slug}')::text,'NULL');")=='NULL'
    query(f"update link_uploads set pending_until=now()-interval '1 second' where id='{items[1]['id']}';")
    assert reserve(9)['id']
    assert query("select has_function_privilege('anon','public.link_get_share(text)','EXECUTE');")=='f'
    assert query("select has_function_privilege('authenticated','public.link_reserve_upload(uuid,uuid,text,bigint,text,timestamptz,bigint,integer)','EXECUTE');")=='f'
    assert query("select has_function_privilege('service_role','public.link_get_share(text)','EXECUTE');")=='t'
    print('Postgres: quota, paid cap, ownership, expiry, 8-way download race, and RPC permissions passed')
finally:
    if started: run(['pg_ctl','-D',str(data),'-m','immediate','-w','stop'])
    shutil.rmtree(root)
