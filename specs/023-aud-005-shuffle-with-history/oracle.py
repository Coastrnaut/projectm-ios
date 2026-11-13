# Independent model of research AUD-005-D1/D4/D5 used to pin the expected sequences.
M=(1<<64)-1
class SM:
    def __init__(s,x): s.s=x&M
    def next(s):
        s.s=(s.s+0x9E3779B97F4A7C15)&M; z=s.s
        z=((z^(z>>30))*0xBF58476D1CE4E5B9)&M; z=((z^(z>>27))*0x94D049BB133111EB)&M
        return z^(z>>31)
def cycle_seed(seed,c): return SM(seed^((c*0x9E3779B97F4A7C15)&M)).next()
def shuffle(ids,seed):
    g=SM(seed); a=list(ids)
    for i in range(len(a)-1,0,-1):
        j=g.next()%(i+1); a[i],a[j]=a[j],a[i]
    return a
class St:
    def __init__(s,seed,ids,cur):
        s.seed=seed; s.cycle=0; s.order=shuffle(ids,cycle_seed(seed,0)); s.played=0; s.hist=[]; s.cur=-1
        if cur is not None:
            if cur in s.order: s.order.remove(cur); s.order.insert(0,cur); s.played=1
            s.hist=[cur]; s.cur=0
    def entry(s): return s.hist[s.cur] if s.cur>=0 else None
    def nextcycle(s,ids):
        a=shuffle(ids,cycle_seed(s.seed,s.cycle+1))
        if len(a)>1 and a[0]==s.entry(): a[0],a[-1]=a[-1],a[0]
        return a
    def upcoming(s,ids):
        if s.cur+1<len(s.hist): return s.hist[s.cur+1]
        if not s.order: return None
        if s.played<len(s.order): return s.order[s.played]
        return s.nextcycle(ids)[0]
    def prev(s): return s.hist[s.cur-1] if s.cur>0 else s.entry()
    def move(s,i,how,ids):
        if how=='prev' and s.cur>0 and s.hist[s.cur-1]==i: s.cur-=1; return
        if how=='next' and s.cur+1<len(s.hist) and s.hist[s.cur+1]==i: s.cur+=1; return
        if s.entry()==i: return
        if i in s.order:
            if s.played==len(s.order):
                s.order=s.nextcycle(ids); s.cycle+=1; s.played=0
            k=s.order.index(i); s.order.pop(k)
            if k<s.played: s.played-=1
            s.order.insert(s.played,i); s.played+=1
        del s.hist[s.cur+1:]; s.hist.append(i); s.cur=len(s.hist)-1
ids=[1,2,3,4,5]
s=St(42,ids,1); seq=[1]
for _ in range(9):
    n=s.upcoming(ids); s.move(n,'next',ids); seq.append(n)
print("two cycles", seq)
s=St(42,ids,1); walk=[]
for how in ['next','next','next','prev','prev','next','next','next']:
    n=s.upcoming(ids) if how=='next' else s.prev(); s.move(n,how,ids); walk.append(n)
print("walk", walk)
for seed in (1,9999):
    s=St(seed,ids,1); q=[1]
    for _ in range(9):
        n=s.upcoming(ids); s.move(n,'next',ids); q.append(n)
    print(seed,q)
