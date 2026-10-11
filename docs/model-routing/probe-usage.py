import tomllib, json, urllib.request, os, glob
cfg=tomllib.load(open(os.path.expanduser("~/.kimi-code/config.toml"),"rb"))
P=cfg.get("providers",{})
def key(n):
    p=P.get(n,{}); return p.get("api_key") or p.get("key"), p.get("base_url")
def get(url,hdr):
    hdr.setdefault("User-Agent","opencode/1.4.0")
    try:
        r=urllib.request.urlopen(urllib.request.Request(url,headers=hdr),timeout=20); return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, e.read()[:300].decode(errors="replace")
    except Exception as e: return None, str(e)[:200]
# Probes plan quotas; keys read from ~/.kimi-code/config.toml, never printed.
print("providers:", sorted(P))
for n in ("minimax-coding-plan","minimax-backup"):
    k,_=key(n)
    if not k: print(n,"no key"); continue
    s,b=get("https://api.minimax.io/v1/token_plan/remains",{"Authorization":"Bearer "+k})
    if isinstance(b,dict):
        for m in b.get("model_remains",[]):
            print(n, {x:m.get(x) for x in ("model_name","current_interval_remaining_percent","current_interval_status","current_weekly_remaining_percent","current_weekly_status","end_time","weekly_end_time")})
    else: print(n,s,b)
k,_=key("ollama-cloud")
if k:
    s,b=get("https://ollama.com/api/balance",{"Authorization":"Bearer "+k}); print("ollama",s,json.dumps(b)[:600] if isinstance(b,dict) else b)
k,_=key("opencode-go")
if k:
    s,b=get("https://opencode.ai/zen/go/v1/usage",{"Authorization":"Bearer "+k,"x-opencode-session":"usage-probe"}); print("opencode-go",s,json.dumps(b)[:1500] if isinstance(b,(dict,list)) else b)

