import { useState, useEffect, useCallback, useMemo } from "react";

// ═══════════════════════════════════════════════════════════════════
// KS PARFUME ERP v3 — FINAL — Sistem Lengkap Parfum
// Fix: HPP dari BOM, Pergerakan Stok ala Olsera, Detail Transaksi,
//      Edit/Hapus semua, Stok Masuk, Import/Export, Offline-first
// ═══════════════════════════════════════════════════════════════════

const SK="ks-parfume-v3f";
const UKURAN=["15ml","20ml","25ml","30ml","35ml","40ml","50ml","55ml","60ml","100ml"];
const KUALITAS=["Medium","Super","Platinum","Full Bibit"];
const METODE=["Cash","QRIS","Transfer"];
const KAT_PENG=["Gaji","Insentif","Operasional","Listrik & Air","Pembelian Bahan","Sewa","Lain-lain"];

const initData=()=>({
  users:[{id:1,nama:"Owner",pin:"1234",peran:"owner"},{id:2,nama:"Kasir 1",pin:"0000",peran:"kasir"},{id:3,nama:"Kasir 2",pin:"1111",peran:"kasir"}],
  produk:[
    {id:1,nama:"BIBIT Ariana Grande Sweet Candy PREMIUM",kat:"STOCK PARFUME",beli:900,stok:50,min:50,sat:"ml"},
    {id:2,nama:"BIBIT Annasui Fantasy Mermaid PREMIUM",kat:"STOCK PARFUME",beli:1000,stok:80,min:50,sat:"ml"},
    {id:3,nama:"BIBIT Aigner Black PREMIUM",kat:"STOCK PARFUME",beli:1500,stok:120,min:50,sat:"ml"},
    {id:4,nama:"BIBIT Aigner Blue PREMIUM",kat:"STOCK PARFUME",beli:900,stok:200,min:50,sat:"ml"},
    {id:5,nama:"BIBIT Baccarat Rouge PREMIUM",kat:"STOCK PARFUME",beli:1000,stok:30,min:50,sat:"ml"},
    {id:6,nama:"BIBIT Dior Sauvage PREMIUM",kat:"STOCK PARFUME",beli:1000,stok:15,min:50,sat:"ml"},
    {id:7,nama:"BIBIT CH Good Girl PREMIUM",kat:"STOCK PARFUME",beli:900,stok:90,min:50,sat:"ml"},
    {id:8,nama:"BIBIT Tom Ford PREMIUM",kat:"STOCK PARFUME",beli:1500,stok:45,min:50,sat:"ml"},
    {id:9,nama:"BIBIT Versace Eros PREMIUM",kat:"STOCK PARFUME",beli:900,stok:110,min:50,sat:"ml"},
    {id:10,nama:"BIBIT Malaikat Subuh",kat:"STOCK PARFUME",beli:900,stok:260,min:50,sat:"ml"},
    {id:11,nama:"BIBIT Kasturi Merah",kat:"STOCK PARFUME",beli:900,stok:137,min:50,sat:"ml"},
    {id:12,nama:"BIBIT Drakar Nuir",kat:"STOCK PARFUME",beli:900,stok:93,min:50,sat:"ml"},
    {id:13,nama:"BIBIT Dior Jadore PREMIUM",kat:"STOCK PARFUME",beli:1000,stok:80,min:50,sat:"ml"},
    {id:14,nama:"BIBIT Chanel Allure PREMIUM",kat:"STOCK PARFUME",beli:1000,stok:65,min:50,sat:"ml"},
    {id:15,nama:"BIBIT Melati",kat:"STOCK PARFUME",beli:400,stok:300,min:50,sat:"ml"},
    {id:16,nama:"BIBIT Mawar",kat:"STOCK PARFUME",beli:350,stok:250,min:50,sat:"ml"},
    {id:50,nama:"STOK BOTOL 15ML",kat:"STOK BOTOL",beli:2500,stok:200,min:30,sat:"pcs"},
    {id:51,nama:"STOK BOTOL 20ML",kat:"STOK BOTOL",beli:3000,stok:180,min:30,sat:"pcs"},
    {id:52,nama:"STOK BOTOL 25ML",kat:"STOK BOTOL",beli:4000,stok:150,min:30,sat:"pcs"},
    {id:53,nama:"STOK BOTOL 30ML",kat:"STOK BOTOL",beli:5600,stok:120,min:30,sat:"pcs"},
    {id:54,nama:"STOK BOTOL 35ML",kat:"STOK BOTOL",beli:5600,stok:100,min:30,sat:"pcs"},
    {id:55,nama:"STOK BOTOL 40ML",kat:"STOK BOTOL",beli:5600,stok:90,min:30,sat:"pcs"},
    {id:56,nama:"STOK BOTOL 50ML",kat:"STOK BOTOL",beli:6000,stok:80,min:30,sat:"pcs"},
    {id:57,nama:"STOK BOTOL 100ML",kat:"STOK BOTOL",beli:7000,stok:60,min:30,sat:"pcs"},
  ],
  varian:[
    {id:"V01",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"15ml",ku:"Medium",hj:30000,rb:8,bid:50},
    {id:"V02",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"15ml",ku:"Super",hj:35000,rb:9,bid:50},
    {id:"V03",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"15ml",ku:"Platinum",hj:45000,rb:11,bid:50},
    {id:"V04",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"30ml",ku:"Medium",hj:55000,rb:15,bid:53},
    {id:"V05",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"30ml",ku:"Super",hj:75000,rb:18,bid:53},
    {id:"V06",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"30ml",ku:"Platinum",hj:85000,rb:21,bid:53},
    {id:"V07",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"50ml",ku:"Medium",hj:90000,rb:25,bid:56},
    {id:"V08",pid:1,nama:"Ariana Grande Sweet Candy PREMIUM",uk:"50ml",ku:"Platinum",hj:140000,rb:35,bid:56},
    {id:"V10",pid:4,nama:"Aigner Blue PREMIUM",uk:"15ml",ku:"Medium",hj:30000,rb:8,bid:50},
    {id:"V11",pid:4,nama:"Aigner Blue PREMIUM",uk:"15ml",ku:"Super",hj:35000,rb:9,bid:50},
    {id:"V12",pid:4,nama:"Aigner Blue PREMIUM",uk:"15ml",ku:"Platinum",hj:45000,rb:11,bid:50},
    {id:"V13",pid:4,nama:"Aigner Blue PREMIUM",uk:"30ml",ku:"Medium",hj:55000,rb:15,bid:53},
    {id:"V14",pid:4,nama:"Aigner Blue PREMIUM",uk:"30ml",ku:"Platinum",hj:85000,rb:21,bid:53},
    {id:"V15",pid:4,nama:"Aigner Blue PREMIUM",uk:"50ml",ku:"Medium",hj:90000,rb:25,bid:56},
    {id:"V20",pid:5,nama:"Baccarat Rouge PREMIUM",uk:"30ml",ku:"Medium",hj:55000,rb:15,bid:53},
    {id:"V21",pid:5,nama:"Baccarat Rouge PREMIUM",uk:"30ml",ku:"Platinum",hj:85000,rb:21,bid:53},
    {id:"V22",pid:6,nama:"Dior Sauvage PREMIUM",uk:"30ml",ku:"Medium",hj:55000,rb:15,bid:53},
    {id:"V23",pid:6,nama:"Dior Sauvage PREMIUM",uk:"30ml",ku:"Platinum",hj:85000,rb:21,bid:53},
    {id:"V30",pid:8,nama:"Tom Ford PREMIUM",uk:"30ml",ku:"Medium",hj:75000,rb:15,bid:53},
    {id:"V31",pid:8,nama:"Tom Ford PREMIUM",uk:"30ml",ku:"Platinum",hj:120000,rb:21,bid:53},
  ],
  transaksi:[
    {id:"T001",tgl:"2026-03-27 09:30",user:"Kasir 1",items:[{vid:"V01",qty:2,hj:30000},{vid:"V10",qty:1,hj:30000}],sub:90000,disk:0,total:90000,bayar:100000,kembali:10000,metode:"Cash"},
    {id:"T002",tgl:"2026-03-27 10:15",user:"Kasir 1",items:[{vid:"V06",qty:1,hj:85000}],sub:85000,disk:5000,total:80000,bayar:80000,kembali:0,metode:"QRIS"},
    {id:"T003",tgl:"2026-03-26 14:00",user:"Kasir 2",items:[{vid:"V31",qty:2,hj:120000}],sub:240000,disk:0,total:240000,bayar:250000,kembali:10000,metode:"Cash"},
  ],
  // Pergerakan Stok (seperti Olsera)
  movement:[
    {id:1,pid:10,tipe:"penjualan",qty:-6,sblm:260,ssdh:254,ket:"Jual Malaikat Subuh x6",tgl:"2026-03-27",user:"Kasir 1"},
    {id:2,pid:13,tipe:"penjualan",qty:-20,sblm:80,ssdh:60,ket:"Jual Dior Jadore x20",tgl:"2026-03-26",user:"Kasir 2"},
    {id:3,pid:12,tipe:"penjualan",qty:-10,sblm:93,ssdh:83,ket:"Jual Drakar Nuir x10",tgl:"2026-03-25",user:"Kasir 1"},
    {id:4,pid:11,tipe:"penjualan",qty:-3,sblm:137,ssdh:134,ket:"Jual Kasturi Merah x3",tgl:"2026-03-25",user:"Kasir 1"},
    {id:5,pid:15,tipe:"penjualan",qty:-8,sblm:300,ssdh:292,ket:"Jual Melati x8",tgl:"2026-03-24",user:"Kasir 2"},
  ],
  stokMasuk:[],
  pengeluaran:[
    {id:1,kat:"Gaji",ket:"Gaji Kasir 1 - Maret",jml:2000000,tgl:"2026-03-25"},
    {id:2,kat:"Operasional",ket:"Listrik Maret",jml:350000,tgl:"2026-03-15"},
    {id:3,kat:"Operasional",ket:"Uang Sampah",jml:50000,tgl:"2026-03-01"},
    {id:4,kat:"Operasional",ket:"Sabun & Tisu",jml:55000,tgl:"2026-03-05"},
  ],
  set:{nama:"KS Parfume Tj. Mulia",alamat:"Medan, Sumatera Utara",telp:"081234567890"},
});

// Helpers
const rp=n=>`Rp ${new Intl.NumberFormat("id-ID").format(n||0)}`;
const tgl=d=>d?new Date(d).toLocaleDateString("id-ID",{day:"2-digit",month:"short",year:"numeric"}):"-";

// Hitung HPP dari BOM (bukan estimasi!)
const hitungHPP=(items,varian,produk)=>items.reduce((a,i)=>{
  const v=varian.find(x=>x.id===i.vid);if(!v)return a;
  const bibit=produk.find(x=>x.id===v.pid);
  const botol=produk.find(x=>x.id===v.bid);
  return a+((bibit?bibit.beli*v.rb:0)+(botol?botol.beli:0))*i.qty;
},0);

// ═══════════════════════════
// APP
// ═══════════════════════════
export default function App(){
  const[d,setD]=useState(null);
  const[user,setUser]=useState(null);
  const[tab,setTab]=useState("beranda");
  const[sb,setSb]=useState(false);
  const[modal,setModal]=useState(null);

  useEffect(()=>{(async()=>{try{const r=await window.storage.get(SK);if(r?.value){setD(JSON.parse(r.value));return;}}catch(e){}setD(initData());})();},[]);

  const sv=useCallback(async nd=>{setD(nd);try{await window.storage.set(SK,JSON.stringify(nd));}catch(e){}},[]);
  const reset=async()=>{const nd=initData();setD(nd);try{await window.storage.set(SK,JSON.stringify(nd));}catch(e){}setModal(null);};

  if(!d)return<div style={{display:"flex",alignItems:"center",justifyContent:"center",height:"100vh",background:"#1a1510",fontFamily:"'DM Sans',sans-serif"}}><link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&family=Cormorant+Garamond:wght@400;600;700&display=swap" rel="stylesheet"/><div style={{textAlign:"center"}}><div style={{fontSize:24,fontWeight:300,letterSpacing:8,color:"#d4a574"}}>KS PARFUME</div><div style={{fontSize:10,letterSpacing:4,color:"#8b7355",marginTop:6}}>Memuat sistem...</div></div></div>;
  if(!user)return<Login users={d.users} onLogin={setUser}/>;

  const own=user.peran==="owner";
  const lowStok=d.produk.filter(p=>p.stok<=p.min);

  const menu=[
    {id:"beranda",lb:"Beranda",ic:"◉"},
    {id:"kasir",lb:"Kasir / POS",ic:"◎"},
    {id:"inventori",lb:"Inventori",ic:"◈"},
    {id:"pergerakan",lb:"Pergerakan Stok",ic:"↕"},
    ...(own?[
      {id:"stokmasuk",lb:"Stok Masuk",ic:"↓"},
      {id:"varian",lb:"Produk & Varian",ic:"◆"},
      {id:"pengeluaran",lb:"Pengeluaran",ic:"◇"},
      {id:"laporan",lb:"Laporan",ic:"◐"},
      {id:"import",lb:"Import / Export",ic:"◑"},
      {id:"pengaturan",lb:"Pengaturan",ic:"◒"},
    ]:[]),
  ];

  return(
    <div style={{display:"flex",height:"100vh",fontFamily:"'DM Sans',sans-serif",background:"#faf8f5",color:"#3a2e24",overflow:"hidden"}}>
      <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&family=Cormorant+Garamond:wght@400;600;700&display=swap" rel="stylesheet"/>

      {/* SIDEBAR */}
      <aside style={{width:sb?215:58,minWidth:sb?215:58,background:"#1a1510",color:"#a09080",display:"flex",flexDirection:"column",transition:"width 0.25s",zIndex:50}}>
        <div onClick={()=>setSb(!sb)} style={{padding:"14px 12px",cursor:"pointer",borderBottom:"1px solid #2a2520",display:"flex",alignItems:"center",gap:10}}>
          <div style={{width:32,height:32,borderRadius:8,background:"linear-gradient(135deg,#d4a574,#b8860b)",display:"flex",alignItems:"center",justifyContent:"center",fontSize:12,fontWeight:700,color:"#fff",flexShrink:0}}>KS</div>
          {sb&&<div><div style={{fontSize:12,fontWeight:700,color:"#f5e6d3",letterSpacing:2}}>KS PARFUME</div><div style={{fontSize:8,color:"#8b7355",letterSpacing:3}}>ERP v3 FINAL</div></div>}
        </div>
        <nav style={{flex:1,padding:"8px 5px",display:"flex",flexDirection:"column",gap:1,overflowY:"auto"}}>
          {menu.map(m=>{const a=tab===m.id;return<button key={m.id} onClick={()=>{setTab(m.id);if(window.innerWidth<768)setSb(false);}} style={{display:"flex",alignItems:"center",gap:9,justifyContent:sb?"flex-start":"center",padding:sb?"8px 12px":"8px 0",background:a?"rgba(212,165,116,0.15)":"transparent",color:a?"#d4a574":"#8b7355",fontWeight:a?600:400,border:"none",borderRadius:7,cursor:"pointer",fontSize:12,width:"100%",position:"relative",transition:"all 0.15s",fontFamily:"inherit"}}>
            {a&&<div style={{position:"absolute",left:0,top:"50%",transform:"translateY(-50%)",width:3,height:16,background:"#d4a574",borderRadius:"0 3px 3px 0"}}/>}
            <span style={{fontSize:15}}>{m.ic}</span>{sb&&<span>{m.lb}</span>}
            {m.id==="inventori"&&lowStok.length>0&&<span style={{background:"#c0392b",color:"#fff",fontSize:8,fontWeight:700,width:14,height:14,borderRadius:"50%",display:"flex",alignItems:"center",justifyContent:"center",position:sb?"static":"absolute",top:2,right:2,marginLeft:sb?"auto":0}}>{lowStok.length}</span>}
          </button>;})}
        </nav>
        <div style={{padding:"8px 5px",borderTop:"1px solid #2a2520"}}>
          <button onClick={()=>{setUser(null);setTab("beranda");}} style={S.sBtn}>{sb?"Keluar ("+user.nama+")":"✕"}</button>
          {own&&<button onClick={()=>setModal("r")} style={{...S.sBtn,marginTop:4,color:"#5c4a3a"}}>{sb?"Reset Data":"↺"}</button>}
        </div>
      </aside>

      <main style={{flex:1,overflow:"auto"}}>
        <header style={{padding:"12px 24px",borderBottom:"1px solid #e8e0d8",display:"flex",justifyContent:"space-between",alignItems:"center",background:"#fff",position:"sticky",top:0,zIndex:20}}>
          <div><h1 style={{margin:0,fontSize:17,fontWeight:700,fontFamily:"'Cormorant Garamond',serif"}}>{menu.find(m=>m.id===tab)?.lb}</h1><p style={{margin:0,fontSize:10,color:"#a09080",marginTop:2}}>Login: <b>{user.nama}</b> ({user.peran})</p></div>
          <div style={{fontSize:11,color:"#a09080",textAlign:"right"}}><div style={{fontWeight:500,color:"#6b5b4b"}}>{new Date().toLocaleDateString("id-ID",{weekday:"long",day:"numeric",month:"long",year:"numeric"})}</div><div>{d.set.nama}</div></div>
        </header>
        <div style={{padding:"20px 24px",maxWidth:1300}}>
          {tab==="beranda"&&<Beranda d={d} own={own} low={lowStok} go={setTab}/>}
          {tab==="kasir"&&<Kasir d={d} sv={sv} user={user}/>}
          {tab==="inventori"&&<Inventori d={d} sv={sv} own={own}/>}
          {tab==="pergerakan"&&<Pergerakan d={d}/>}
          {tab==="stokmasuk"&&<StokMasuk d={d} sv={sv} user={user}/>}
          {tab==="varian"&&<Varian d={d} sv={sv}/>}
          {tab==="pengeluaran"&&<Pengeluaran d={d} sv={sv}/>}
          {tab==="laporan"&&<Laporan d={d}/>}
          {tab==="import"&&<ImpExp d={d} sv={sv}/>}
          {tab==="pengaturan"&&<Pengaturan d={d} sv={sv}/>}
        </div>
      </main>

      {modal==="r"&&<Ov onClose={()=>setModal(null)}><div style={{background:"#fff",borderRadius:16,padding:24,width:380}}>
        <h3 style={{margin:"0 0 8px",fontSize:16,fontFamily:"'Cormorant Garamond',serif"}}>Reset Semua Data?</h3>
        <p style={{color:"#8b7355",fontSize:13}}>Semua data kembali ke awal.</p>
        <div style={{display:"flex",gap:10,marginTop:16}}><button onClick={()=>setModal(null)} style={{...S.btn2,flex:1}}>Batal</button><button onClick={reset} style={{...S.btn1,flex:1,background:"#c0392b"}}>Ya, Reset</button></div>
      </div></Ov>}
    </div>
  );
}

// ═══════ KOMPONEN DASAR ═══════
const Ov=({children,onClose})=><div onClick={onClose} style={{position:"fixed",inset:0,background:"rgba(0,0,0,0.5)",zIndex:200,display:"flex",alignItems:"center",justifyContent:"center",padding:16}}><div onClick={e=>e.stopPropagation()} style={{maxHeight:"90vh",overflowY:"auto"}}>{children}</div></div>;
const K=({children,s,klik})=><div onClick={klik} style={{background:"#fff",borderRadius:12,border:"1px solid #e8e0d8",padding:16,...(klik?{cursor:"pointer"}:{}),...s}}>{children}</div>;
const J=({children,aksi})=><div style={{display:"flex",justifyContent:"space-between",alignItems:"center",margin:"24px 0 12px",flexWrap:"wrap",gap:8}}><h2 style={{margin:0,fontSize:15,fontWeight:600,fontFamily:"'Cormorant Garamond',serif"}}>{children}</h2>{aksi}</div>;
const L=({s})=>{const c={Cash:"#27ae60",QRIS:"#2980b9",Transfer:"#d4a574",Gaji:"#8e44ad",Operasional:"#e67e22","Listrik & Air":"#2980b9","Pembelian Bahan":"#c0392b","Lain-lain":"#95a5a6",masuk:"#27ae60",penjualan:"#2980b9",keluar:"#e67e22",return:"#8e44ad",opname:"#d4a574"};const cl=c[s]||"#95a5a6";return<span style={{padding:"2px 10px",borderRadius:12,fontSize:10,fontWeight:600,background:cl+"18",color:cl}}>{s}</span>;};
const KPI=({lb,val,sub,clr,klik})=><K klik={klik}><div style={{fontSize:9,color:"#a09080",fontWeight:600,letterSpacing:1,textTransform:"uppercase",marginBottom:5}}>{lb}</div><div style={{fontSize:22,fontWeight:700,color:clr||"#3a2e24"}}>{val}</div>{sub&&<div style={{fontSize:10,color:"#a09080",marginTop:3}}>{sub}</div>}</K>;
const Bar=({v,m=100,w="#d4a574"})=><div style={{width:60,height:4,background:"#f0ebe4",borderRadius:2,overflow:"hidden"}}><div style={{width:`${Math.min(v/m*100,100)}%`,height:"100%",background:w,borderRadius:2}}/></div>;

const T=({cols,rows,empty})=>(
  <div style={{overflowX:"auto",borderRadius:10,border:"1px solid #e8e0d8"}}>
    <table style={{width:"100%",borderCollapse:"collapse",fontSize:12}}>
      <thead><tr style={{background:"#faf8f5"}}>{cols.map((c,i)=><th key={i} style={{padding:"8px 10px",textAlign:c.r||"left",fontWeight:600,fontSize:9,color:"#a09080",textTransform:"uppercase",letterSpacing:.5,whiteSpace:"nowrap"}}>{c.l}</th>)}</tr></thead>
      <tbody>{(!rows||!rows.length)?<tr><td colSpan={cols.length} style={{padding:30,textAlign:"center",color:"#a09080"}}>{empty||"Tidak ada data"}</td></tr>:rows.map((b,i)=><tr key={i} style={{borderTop:"1px solid #f0ebe4"}} onMouseEnter={e=>e.currentTarget.style.background="#faf8f5"} onMouseLeave={e=>e.currentTarget.style.background="transparent"}>{cols.map((c,j)=><td key={j} style={{padding:"9px 10px",textAlign:c.r||"left",whiteSpace:c.wrap?"normal":"nowrap"}}>{c.c?c.c(b,i):b[c.k]}</td>)}</tr>)}</tbody>
    </table>
  </div>
);

const S={
  inp:{width:"100%",padding:"8px 12px",borderRadius:8,border:"1px solid #e8e0d8",fontSize:12,boxSizing:"border-box",fontFamily:"inherit",background:"#fff"},
  lbl:{fontSize:10,color:"#a09080",display:"block",marginBottom:3,fontWeight:500},
  btn1:{padding:"8px 16px",borderRadius:8,border:"none",background:"#d4a574",color:"#fff",fontSize:12,fontWeight:600,cursor:"pointer",fontFamily:"inherit"},
  btn2:{padding:"8px 16px",borderRadius:8,border:"none",background:"#f0ebe4",color:"#6b5b4b",fontSize:12,fontWeight:600,cursor:"pointer",fontFamily:"inherit"},
  btnDel:{background:"#fde8e8",border:"none",borderRadius:4,padding:"2px 8px",fontSize:9,cursor:"pointer",color:"#c0392b"},
  qBtn:{width:24,height:24,borderRadius:6,border:"1px solid #e8e0d8",background:"#fff",cursor:"pointer",fontSize:13,display:"flex",alignItems:"center",justifyContent:"center"},
  sBtn:{display:"flex",alignItems:"center",gap:6,width:"100%",padding:6,background:"transparent",border:"1px solid #2a2520",color:"#8b7355",borderRadius:6,cursor:"pointer",fontSize:10,justifyContent:"center",fontFamily:"inherit"},
};

// ═══════ LOGIN ═══════
function Login({users,onLogin}){
  const[pin,setPin]=useState("");const[err,setErr]=useState("");
  const cek=p=>{const u=users.find(u=>u.pin===p);if(u){onLogin(u);setPin("");setErr("");}else{setErr("PIN salah!");setPin("");}};
  return<div style={{display:"flex",alignItems:"center",justifyContent:"center",height:"100vh",background:"linear-gradient(135deg,#1a1510,#2a2118,#1a1510)",fontFamily:"'DM Sans',sans-serif"}}>
    <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&family=Cormorant+Garamond:wght@400;600;700&display=swap" rel="stylesheet"/>
    <div style={{width:340,textAlign:"center"}}>
      <div style={{width:70,height:70,borderRadius:20,background:"linear-gradient(135deg,#d4a574,#b8860b)",margin:"0 auto 16px",display:"flex",alignItems:"center",justifyContent:"center",fontSize:22,fontWeight:700,color:"#fff"}}>KS</div>
      <div style={{fontSize:22,fontWeight:300,letterSpacing:6,color:"#d4a574",marginBottom:4,fontFamily:"'Cormorant Garamond',serif"}}>KS PARFUME</div>
      <div style={{fontSize:10,letterSpacing:4,color:"#8b7355",marginBottom:36}}>SISTEM ERP</div>
      <div style={{background:"#2a2520",borderRadius:16,padding:28,border:"1px solid #3a3530"}}>
        <div style={{fontSize:13,color:"#d4a574",marginBottom:16,fontWeight:500}}>Masukkan PIN untuk login</div>
        <div style={{display:"flex",justifyContent:"center",gap:8,marginBottom:20}}>{[0,1,2,3].map(i=><div key={i} style={{width:40,height:48,borderRadius:10,background:pin[i]?"rgba(212,165,116,0.2)":"#1a1510",border:`2px solid ${pin[i]?"#d4a574":"#3a3530"}`,display:"flex",alignItems:"center",justifyContent:"center",fontSize:20,color:"#d4a574",fontWeight:700}}>{pin[i]?"●":""}</div>)}</div>
        <div style={{display:"grid",gridTemplateColumns:"repeat(3,1fr)",gap:8,maxWidth:220,margin:"0 auto"}}>{[1,2,3,4,5,6,7,8,9,"",0,"⌫"].map((n,i)=>n===""?<div key={i}/>:<button key={i} onClick={()=>{if(n==="⌫")setPin(pin.slice(0,-1));else if(pin.length<4){const np=pin+n;setPin(np);if(np.length===4)setTimeout(()=>cek(np),200);}}} style={{width:56,height:48,borderRadius:10,border:"none",background:n==="⌫"?"transparent":"#1a1510",color:n==="⌫"?"#8b7355":"#d4a574",fontSize:n==="⌫"?18:20,fontWeight:600,cursor:"pointer"}}>{n}</button>)}</div>
        {err&&<div style={{color:"#e74c3c",fontSize:12,marginTop:12}}>{err}</div>}
        <div style={{marginTop:20,fontSize:10,color:"#5c4a3a"}}>Owner: 1234 | Kasir 1: 0000 | Kasir 2: 1111</div>
      </div>
    </div>
  </div>;
}

// ═══════ BERANDA ═══════
function Beranda({d,own,low,go}){
  const today=new Date().toISOString().slice(0,10);
  const trxH=d.transaksi.filter(t=>t.tgl.startsWith(today));
  const pend=trxH.reduce((a,t)=>a+t.total,0);
  const hpp=trxH.reduce((a,t)=>a+hitungHPP(t.items,d.varian,d.produk),0);
  const pengBulan=d.pengeluaran.filter(p=>p.tgl.startsWith(today.slice(0,7))).reduce((a,p)=>a+p.jml,0);

  return<div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(155px,1fr))",gap:10}}>
      <KPI lb="Pendapatan Hari Ini" val={rp(pend)} sub={`${trxH.length} transaksi`} clr="#27ae60"/>
      {own&&<KPI lb="HPP (dari Resep)" val={rp(hpp)} sub="Hitung otomatis BOM" clr="#c0392b"/>}
      {own&&<KPI lb="Laba Kotor" val={rp(pend-hpp)} clr="#d4a574"/>}
      {own&&<KPI lb="Pengeluaran Bulan" val={rp(pengBulan)} clr="#e67e22"/>}
      <KPI lb="Total Produk" val={d.produk.length} klik={()=>go("inventori")}/>
      <KPI lb="Total Varian" val={d.varian.length} klik={()=>own&&go("varian")}/>
    </div>
    {low.length>0&&<><J>⚠ Stok Rendah — Perlu Restock!</J><K s={{background:"#fdf0e8",borderColor:"#e8c9a8"}}>{low.slice(0,6).map(p=><div key={p.id} style={{display:"flex",alignItems:"center",gap:8,padding:"5px 0",borderBottom:"1px solid #f0dcc8",fontSize:12}}><span style={{color:"#c0392b"}}>⚠</span><span style={{fontWeight:500,flex:1}}>{p.nama}</span><span style={{color:"#c0392b",fontWeight:600}}>{p.stok} {p.sat}</span><span style={{color:"#a09080",fontSize:10}}>min: {p.min}</span></div>)}</K></>}
    <J>Transaksi Terakhir</J>
    <T cols={[
      {l:"No",c:r=><b style={{fontSize:11}}>{r.id}</b>},
      {l:"Waktu",c:r=><span style={{fontSize:11}}>{r.tgl}</span>},
      {l:"Kasir",c:r=>r.user},
      {l:"Item",c:r=>r.items.map(i=>{const v=d.varian.find(x=>x.id===i.vid);return v?v.nama.split(" ")[0]+" "+v.uk+" "+v.ku:"?";}).join(", ").slice(0,50),wrap:true},
      {l:"HPP",r:"right",c:r=><span style={{color:"#c0392b",fontSize:10}}>{rp(hitungHPP(r.items,d.varian,d.produk))}</span>},
      {l:"Total",r:"right",c:r=><b>{rp(r.total)}</b>},
      {l:"Metode",c:r=><L s={r.metode}/>},
    ]} rows={d.transaksi.slice(0,8)}/>
  </div>;
}

// ═══════ KASIR / POS ═══════
function Kasir({d,sv,user}){
  const[cari,setCari]=useState("");const[cart,setCart]=useState([]);const[met,setMet]=useState("Cash");const[bayar,setBayar]=useState("");const[disk,setDisk]=useState(0);const[pilih,setPilih]=useState(null);const[sukses,setSukses]=useState(null);

  const pids=[...new Set(d.varian.map(v=>v.pid))];
  const prods=pids.map(id=>{const p=d.produk.find(x=>x.id===id);const vs=d.varian.filter(v=>v.pid===id);return p?{...p,vc:vs.length,nj:vs[0]?.nama||p.nama}:null;}).filter(Boolean).filter(p=>p.nj.toLowerCase().includes(cari.toLowerCase()));

  const sub=cart.reduce((a,k)=>a+k.hj*k.qty,0);const tot=Math.max(sub-disk,0);const bay=parseInt((bayar+"").replace(/\D/g,""))||0;

  const tambah=v=>{
    const bibit=d.produk.find(p=>p.id===v.pid);if(bibit&&bibit.stok<v.rb){alert(`Stok ${bibit.nama} kurang! Sisa: ${bibit.stok} ml`);return;}
    const botol=d.produk.find(p=>p.id===v.bid);if(botol&&botol.stok<1){alert(`Stok ${botol.nama} habis!`);return;}
    const idx=cart.findIndex(k=>k.vid===v.id);
    if(idx>=0){const b=[...cart];b[idx].qty+=1;setCart(b);}
    else setCart([...cart,{vid:v.id,nama:`${v.nama} ${v.uk} ${v.ku}`,hj:v.hj,qty:1}]);
    setPilih(null);
  };

  const proses=()=>{
    if(!cart.length||bay<tot)return;
    const pb=[...d.produk];const mvs=[...d.movement];let mvId=Math.max(0,...mvs.map(m=>m.id))+1;
    cart.forEach(k=>{
      const v=d.varian.find(x=>x.id===k.vid);if(!v)return;
      const ib=pb.findIndex(p=>p.id===v.pid);const ibo=pb.findIndex(p=>p.id===v.bid);
      if(ib>=0){const old=pb[ib].stok;pb[ib]={...pb[ib],stok:old-(v.rb*k.qty)};
        mvs.push({id:mvId++,pid:v.pid,tipe:"penjualan",qty:-(v.rb*k.qty),sblm:old,ssdh:pb[ib].stok,ket:`Jual ${k.nama} x${k.qty}`,tgl:new Date().toISOString().slice(0,10),user:user.nama});}
      if(ibo>=0){const old=pb[ibo].stok;pb[ibo]={...pb[ibo],stok:old-k.qty};
        mvs.push({id:mvId++,pid:v.bid,tipe:"penjualan",qty:-k.qty,sblm:old,ssdh:pb[ibo].stok,ket:`Botol untuk ${k.nama} x${k.qty}`,tgl:new Date().toISOString().slice(0,10),user:user.nama});}
    });
    const trx={id:`T${String(d.transaksi.length+1).padStart(3,"0")}`,tgl:new Date().toISOString().slice(0,16).replace("T"," "),user:user.nama,items:cart.map(k=>({vid:k.vid,qty:k.qty,hj:k.hj})),sub,disk,total:tot,bayar:bay,kembali:Math.max(bay-tot,0),metode:met};
    sv({...d,transaksi:[trx,...d.transaksi],produk:pb,movement:mvs});
    setSukses({total:tot,kembali:Math.max(bay-tot,0),metode:met,no:trx.id});setCart([]);setBayar("");setDisk(0);
  };

  return<div style={{display:"grid",gridTemplateColumns:"1fr 330px",gap:16,minHeight:480}}>
    <div>
      <input value={cari} onChange={e=>setCari(e.target.value)} placeholder="🔍 Cari parfum..." style={S.inp}/>
      <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(170px,1fr))",gap:8,marginTop:8}}>
        {prods.map(p=><K key={p.id} klik={()=>setPilih(p.id)} s={{padding:12}}><div style={{fontWeight:600,fontSize:12,marginBottom:3}}>{p.nj}</div><div style={{fontSize:10,color:"#a09080"}}>{p.vc} varian · stok: {p.stok} {p.sat}</div><div style={{fontSize:10,color:p.stok<=p.min?"#c0392b":"#27ae60",fontWeight:500,marginTop:2}}>{p.stok<=p.min?"⚠ Stok rendah":"✓ Tersedia"}</div></K>)}
      </div>
    </div>
    <div style={{background:"#fff",borderRadius:12,border:"1px solid #e8e0d8",padding:14,display:"flex",flexDirection:"column"}}>
      <div style={{fontSize:14,fontWeight:700,marginBottom:10,fontFamily:"'Cormorant Garamond',serif"}}>Keranjang ({cart.length})</div>
      <div style={{flex:1,overflowY:"auto",marginBottom:10}}>
        {!cart.length?<p style={{color:"#a09080",fontSize:11,textAlign:"center",marginTop:30}}>Pilih parfum untuk mulai</p>:
          cart.map((k,i)=><div key={i} style={{display:"flex",alignItems:"center",gap:6,padding:"7px 0",borderBottom:"1px solid #f0ebe4"}}>
            <div style={{flex:1}}><div style={{fontSize:11,fontWeight:500}}>{k.nama}</div><div style={{fontSize:10,color:"#a09080"}}>{rp(k.hj)}</div></div>
            <button onClick={()=>{const b=[...cart];b[i].qty=Math.max(b[i].qty-1,0);if(!b[i].qty)b.splice(i,1);setCart(b);}} style={S.qBtn}>−</button>
            <span style={{fontSize:12,fontWeight:700,minWidth:16,textAlign:"center"}}>{k.qty}</span>
            <button onClick={()=>{const b=[...cart];b[i].qty+=1;setCart(b);}} style={S.qBtn}>+</button>
            <span style={{fontWeight:600,fontSize:11,minWidth:60,textAlign:"right"}}>{rp(k.hj*k.qty)}</span>
            <button onClick={()=>{const b=[...cart];b.splice(i,1);setCart(b);}} style={{...S.qBtn,color:"#c0392b",borderColor:"#f0d0c0",fontSize:10}}>✕</button>
          </div>)}
      </div>
      <div style={{borderTop:"2px solid #e8e0d8",paddingTop:10}}>
        <div style={{display:"flex",justifyContent:"space-between",fontSize:11,marginBottom:3}}><span style={{color:"#a09080"}}>Subtotal</span><span>{rp(sub)}</span></div>
        <div style={{display:"flex",gap:6,alignItems:"center",marginBottom:3}}><span style={{fontSize:11,color:"#a09080"}}>Diskon</span><input type="number" value={disk||""} onChange={e=>setDisk(parseInt(e.target.value)||0)} style={{...S.inp,flex:1,padding:"4px 8px",textAlign:"right",fontSize:11}}/></div>
        <div style={{display:"flex",justifyContent:"space-between",fontSize:16,fontWeight:700,margin:"8px 0",color:"#d4a574"}}><span>TOTAL</span><span>{rp(tot)}</span></div>
        <div style={{display:"flex",gap:4,marginBottom:8}}>{METODE.map(m=><button key={m} onClick={()=>setMet(m)} style={{flex:1,padding:5,borderRadius:6,border:`1px solid ${met===m?"#d4a574":"#e8e0d8"}`,background:met===m?"#d4a574":"#fff",color:met===m?"#fff":"#6b5b4b",fontSize:10,fontWeight:500,cursor:"pointer"}}>{m}</button>)}</div>
        <input value={bayar} onChange={e=>setBayar(e.target.value)} placeholder="Jumlah bayar..." style={{...S.inp,marginBottom:6}}/>
        {bay>0&&bay>=tot&&<div style={{fontSize:11,color:"#27ae60",fontWeight:600,marginBottom:6}}>Kembalian: {rp(bay-tot)}</div>}
        <button onClick={proses} disabled={!cart.length||bay<tot} style={{width:"100%",padding:12,borderRadius:10,border:"none",background:cart.length&&bay>=tot?"#d4a574":"#e8e0d8",color:cart.length&&bay>=tot?"#fff":"#a09080",fontSize:14,fontWeight:700,cursor:"pointer"}}>Bayar Sekarang</button>
      </div>
    </div>

    {pilih&&<Ov onClose={()=>setPilih(null)}><div style={{background:"#fff",borderRadius:16,padding:24,width:480,maxWidth:"95vw"}}>
      <div style={{display:"flex",justifyContent:"space-between",marginBottom:16}}><h3 style={{margin:0,fontSize:16,fontFamily:"'Cormorant Garamond',serif"}}>Pilih Ukuran & Kualitas</h3><button onClick={()=>setPilih(null)} style={{background:"none",border:"none",fontSize:18,cursor:"pointer",color:"#a09080"}}>✕</button></div>
      {(()=>{const vs=d.varian.filter(v=>v.pid===pilih);const uks=[...new Set(vs.map(v=>v.uk))];const bibit=d.produk.find(p=>p.id===pilih);
        return<div><div style={{fontSize:12,color:"#a09080",marginBottom:12,padding:"6px 10px",background:"#faf8f5",borderRadius:6}}>Stok bibit: <b style={{color:bibit?.stok<=bibit?.min?"#c0392b":"#27ae60"}}>{bibit?.stok} ml</b></div>
          {uks.map(uk=><div key={uk} style={{marginBottom:12}}><div style={{fontSize:11,fontWeight:600,color:"#6b5b4b",marginBottom:6,padding:"4px 10px",background:"#faf8f5",borderRadius:6}}>{uk}</div>
            <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(120px,1fr))",gap:6}}>{vs.filter(v=>v.uk===uk).map(v=>{const ok=bibit&&bibit.stok>=v.rb;return<K key={v.id} klik={ok?()=>tambah(v):undefined} s={{padding:10,opacity:ok?1:0.4}}><div style={{fontWeight:600,fontSize:12}}>{v.ku}</div><div style={{fontSize:14,fontWeight:700,color:"#d4a574",margin:"3px 0"}}>{rp(v.hj)}</div><div style={{fontSize:9,color:"#a09080"}}>Bibit: {v.rb}ml {!ok&&"⚠"}</div></K>;})}</div>
          </div>)}</div>;})()}
    </div></Ov>}

    {sukses&&<Ov onClose={()=>setSukses(null)}><div style={{background:"#fff",borderRadius:16,padding:28,width:350,textAlign:"center"}}>
      <div style={{fontSize:40,marginBottom:8}}>✓</div><div style={{fontSize:18,fontWeight:700,fontFamily:"'Cormorant Garamond',serif"}}>Pembayaran Berhasil!</div>
      <div style={{fontSize:11,color:"#a09080"}}>{sukses.no}</div><div style={{fontSize:28,fontWeight:700,color:"#27ae60",margin:"12px 0"}}>{rp(sukses.total)}</div><L s={sukses.metode}/>
      {sukses.kembali>0&&<div style={{fontSize:16,fontWeight:600,color:"#d4a574",marginTop:8}}>Kembalian: {rp(sukses.kembali)}</div>}
      <button onClick={()=>setSukses(null)} style={{...S.btn1,width:"100%",marginTop:16}}>Tutup</button>
    </div></Ov>}
  </div>;
}

// ═══════ INVENTORI ═══════
function Inventori({d,sv,own}){
  const[f,setF]=useState("semua");const[eid,setEid]=useState(null);const[es,setEs]=useState("");
  const kats=["semua",...new Set(d.produk.map(p=>p.kat))];
  const fl=f==="semua"?d.produk:d.produk.filter(p=>p.kat===f);
  return<div>
    <div style={{display:"flex",gap:5,marginBottom:14,flexWrap:"wrap"}}>{kats.map(k=><button key={k} onClick={()=>setF(k)} style={{padding:"4px 12px",borderRadius:14,border:`1px solid ${f===k?"#d4a574":"#e8e0d8"}`,background:f===k?"#d4a574":"#fff",color:f===k?"#fff":"#6b5b4b",fontSize:10,fontWeight:500,cursor:"pointer"}}>{k==="semua"?"Semua":k}</button>)}</div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(155px,1fr))",gap:10,marginBottom:14}}>
      <KPI lb="Total Item" val={d.produk.length} clr="#2980b9"/><KPI lb="Stok Aman" val={d.produk.filter(p=>p.stok>p.min).length} clr="#27ae60"/><KPI lb="Stok Kritis" val={d.produk.filter(p=>p.stok<=p.min).length} clr="#c0392b"/><KPI lb="Nilai Inventori" val={rp(d.produk.reduce((a,p)=>a+p.stok*p.beli,0))} clr="#d4a574"/>
    </div>
    <T cols={[
      {l:"Produk",c:r=><div><div style={{fontWeight:500,fontSize:11}}>{r.nama}</div><div style={{fontSize:9,color:"#a09080"}}>{r.kat}</div></div>,wrap:true},
      {l:"Stok",r:"right",c:r=><div style={{display:"flex",alignItems:"center",gap:4,justifyContent:"flex-end"}}><Bar v={r.stok} m={r.min*5} w={r.stok<=r.min?"#c0392b":"#27ae60"}/><span style={{fontWeight:600,color:r.stok<=r.min?"#c0392b":"#3a2e24",fontSize:11}}>{r.stok} {r.sat}</span></div>},
      {l:"Min",r:"right",c:r=><span style={{color:"#a09080",fontSize:10}}>{r.min}</span>},
      {l:"Harga Beli",r:"right",c:r=><span style={{fontSize:10}}>{rp(r.beli)}</span>},
      {l:"Status",c:r=>r.stok<=r.min?<span style={{color:"#c0392b",fontSize:9,fontWeight:700}}>⚠ RESTOCK</span>:<span style={{color:"#27ae60",fontSize:9,fontWeight:600}}>✓ OK</span>},
      ...(own?[{l:"Aksi",c:r=><div style={{display:"flex",gap:4}}>
        {eid===r.id?<><input value={es} onChange={e=>setEs(e.target.value)} style={{width:50,padding:"2px 4px",borderRadius:4,border:"1px solid #d4a574",fontSize:11,textAlign:"center"}}/><button onClick={()=>{sv({...d,produk:d.produk.map(p=>p.id===r.id?{...p,stok:parseInt(es)||0}:p)});setEid(null);}} style={{background:"#27ae60",color:"#fff",border:"none",borderRadius:4,padding:"2px 6px",fontSize:9,cursor:"pointer"}}>✓</button><button onClick={()=>setEid(null)} style={S.btnDel}>✕</button></>:
        <><button onClick={()=>{setEid(r.id);setEs(String(r.stok));}} style={S.btn2}>Edit</button><button onClick={()=>{if(confirm("Hapus produk ini?"))sv({...d,produk:d.produk.filter(p=>p.id!==r.id),varian:d.varian.filter(v=>v.pid!==r.id&&v.bid!==r.id)});}} style={S.btnDel}>Hapus</button></>}
      </div>}]:[]),
    ]} rows={fl}/>
  </div>;
}

// ═══════ PERGERAKAN STOK (seperti Olsera!) ═══════
function Pergerakan({d}){
  const[tipe,setTipe]=useState("semua");
  const tipes=["semua","masuk","penjualan","keluar","return","opname"];

  // Hitung ringkasan per produk (seperti Olsera)
  const bibitBotol=d.produk.filter(p=>["STOCK PARFUME","STOK BOTOL"].includes(p.kat));
  const ringkasan=bibitBotol.map(p=>{
    const mvs=d.movement.filter(m=>m.pid===p.id);
    const masuk=mvs.filter(m=>m.tipe==="masuk").reduce((a,m)=>a+Math.abs(m.qty),0);
    const penjualan=mvs.filter(m=>m.tipe==="penjualan").reduce((a,m)=>a+Math.abs(m.qty),0);
    const keluar=mvs.filter(m=>m.tipe==="keluar").reduce((a,m)=>a+Math.abs(m.qty),0);
    const ret=mvs.filter(m=>m.tipe==="return").reduce((a,m)=>a+Math.abs(m.qty),0);
    const awal=p.stok+penjualan+keluar-masuk-ret;
    return{...p,awal,masuk,ret,penjualan,keluar,sisa:p.stok};
  });

  const filtered=tipe==="semua"?d.movement:d.movement.filter(m=>m.tipe===tipe);

  return<div>
    {/* Tab filter seperti Olsera */}
    <div style={{display:"flex",gap:5,marginBottom:16,flexWrap:"wrap"}}>{tipes.map(t=><button key={t} onClick={()=>setTipe(t)} style={{padding:"5px 14px",borderRadius:14,border:`1px solid ${tipe===t?"#d4a574":"#e8e0d8"}`,background:tipe===t?"#d4a574":"#fff",color:tipe===t?"#fff":"#6b5b4b",fontSize:11,fontWeight:500,cursor:"pointer",textTransform:"capitalize"}}>{t==="semua"?"Semua":t}</button>)}</div>

    {/* Ringkasan Olsera-style */}
    <J>Ringkasan Pergerakan Stok</J>
    <div style={{fontSize:11,color:"#a09080",marginBottom:8}}>{ringkasan.length} Item</div>
    <T cols={[
      {l:"Grup",c:r=><span style={{fontSize:10,color:"#6b5b4b"}}>{r.kat}</span>},
      {l:"Produk",c:r=><span style={{fontWeight:500,fontSize:11}}>{r.nama}</span>,wrap:true},
      {l:"Awal",r:"right",c:r=><span style={{fontWeight:500}}>{r.awal}</span>},
      {l:"Masuk",r:"right",c:r=><span style={{color:r.masuk>0?"#27ae60":"#a09080",fontWeight:r.masuk>0?600:400}}>{r.masuk}</span>},
      {l:"Return",r:"right",c:r=><span style={{color:r.ret>0?"#8e44ad":"#a09080"}}>{r.ret}</span>},
      {l:"Penjualan",r:"right",c:r=><span style={{color:r.penjualan>0?"#2980b9":"#a09080",fontWeight:r.penjualan>0?600:400}}>{r.penjualan}</span>},
      {l:"Keluar",r:"right",c:r=><span style={{color:r.keluar>0?"#e67e22":"#a09080"}}>{r.keluar}</span>},
      {l:"Sisa",r:"right",c:r=><span style={{fontWeight:700,color:r.sisa<=r.min?"#c0392b":"#3a2e24"}}>{r.sisa}</span>},
    ]} rows={ringkasan} empty="Belum ada data pergerakan stok"/>

    {/* Detail Log */}
    <J>Detail Pergerakan</J>
    <T cols={[
      {l:"Tanggal",c:r=>tgl(r.tgl)},
      {l:"Produk",c:r=>{const p=d.produk.find(x=>x.id===r.pid);return<span style={{fontSize:11}}>{p?.nama||"-"}</span>;},wrap:true},
      {l:"Tipe",c:r=><L s={r.tipe}/>},
      {l:"Qty",r:"right",c:r=><span style={{fontWeight:600,color:r.qty>=0?"#27ae60":"#c0392b"}}>{r.qty>=0?"+":""}{r.qty}</span>},
      {l:"Sebelum",r:"right",c:r=><span style={{fontSize:10,color:"#a09080"}}>{r.sblm}</span>},
      {l:"Sesudah",r:"right",c:r=><span style={{fontSize:10,fontWeight:500}}>{r.ssdh}</span>},
      {l:"Keterangan",c:r=><span style={{fontSize:10,color:"#6b5b4b"}}>{r.ket}</span>,wrap:true},
      {l:"User",c:r=><span style={{fontSize:10}}>{r.user}</span>},
    ]} rows={filtered.slice(0,100)} empty="Belum ada pergerakan"/>
  </div>;
}

// ═══════ STOK MASUK ═══════
function StokMasuk({d,sv,user}){
  const[items,setItems]=useState([{pid:"",qty:""}]);
  const bibitBotol=d.produk.filter(p=>["STOCK PARFUME","STOK BOTOL"].includes(p.kat));

  const proses=()=>{
    const valid=items.filter(i=>i.pid&&i.qty);if(!valid.length){alert("Lengkapi data!");return;}
    const pb=[...d.produk];const mvs=[...d.movement];let mvId=Math.max(0,...mvs.map(m=>m.id))+1;
    const smBaru=[...d.stokMasuk];let smId=Math.max(0,...smBaru.map(s=>s.id||0))+1;
    valid.forEach(it=>{
      const idx=pb.findIndex(p=>p.id===it.pid);if(idx<0)return;
      const old=pb[idx].stok;const qty=parseInt(it.qty)||0;
      pb[idx]={...pb[idx],stok:old+qty};
      mvs.push({id:mvId++,pid:it.pid,tipe:"masuk",qty,sblm:old,ssdh:old+qty,ket:`Stok masuk: ${pb[idx].nama}`,tgl:new Date().toISOString().slice(0,10),user:user.nama});
      smBaru.push({id:smId++,pid:it.pid,nama:pb[idx].nama,qty,tgl:new Date().toISOString().slice(0,10),user:user.nama});
    });
    sv({...d,produk:pb,movement:mvs,stokMasuk:smBaru});
    setItems([{pid:"",qty:""}]);alert("✅ Stok masuk berhasil dicatat!");
  };

  return<div>
    <K>
      <h3 style={{margin:"0 0 16px",fontSize:14,fontFamily:"'Cormorant Garamond',serif"}}>Catat Stok Masuk (Pembelian Bahan)</h3>
      <div style={{display:"flex",justifyContent:"space-between",marginBottom:8}}><label style={S.lbl}>Item Pembelian</label><button onClick={()=>setItems([...items,{pid:"",qty:""}])} style={S.btn2}>+ Tambah Baris</button></div>
      {items.map((it,i)=><div key={i} style={{display:"grid",gridTemplateColumns:"2fr 1fr auto",gap:8,marginBottom:8}}>
        <select value={it.pid} onChange={e=>{const b=[...items];b[i].pid=e.target.value;setItems(b);}} style={S.inp}><option value="">Pilih Produk</option>{bibitBotol.map(p=><option key={p.id} value={p.id}>{p.nama} (stok: {p.stok})</option>)}</select>
        <input type="number" value={it.qty} onChange={e=>{const b=[...items];b[i].qty=e.target.value;setItems(b);}} placeholder="Qty" style={S.inp}/>
        <button onClick={()=>{const b=[...items];b.splice(i,1);if(!b.length)b.push({pid:"",qty:""});setItems(b);}} style={S.btnDel}>✕</button>
      </div>)}
      <button onClick={proses} style={S.btn1}>💾 Simpan Stok Masuk</button>
    </K>

    {d.stokMasuk.length>0&&<><J>Riwayat Stok Masuk</J>
      <T cols={[{l:"Tanggal",c:r=>tgl(r.tgl)},{l:"Produk",c:r=><span style={{fontWeight:500}}>{r.nama}</span>,wrap:true},{l:"Qty",r:"right",c:r=><span style={{color:"#27ae60",fontWeight:600}}>+{r.qty}</span>},{l:"User",c:r=>r.user}]} rows={d.stokMasuk.slice().reverse()}/>
    </>}
  </div>;
}

// ═══════ VARIAN ═══════
function Varian({d,sv}){
  const[cari,setCari]=useState("");const[show,setShow]=useState(false);
  const[fm,setFm]=useState({pid:"",uk:"30ml",ku:"Medium",hj:"",rb:"15",bid:""});
  const gr={};d.varian.filter(v=>v.nama.toLowerCase().includes(cari.toLowerCase())).forEach(v=>{if(!gr[v.pid])gr[v.pid]={p:d.produk.find(p=>p.id===v.pid),vs:[]};gr[v.pid].vs.push(v);});

  const simpan=()=>{if(!fm.pid||!fm.hj)return;const bibit=d.produk.find(p=>p.id===parseInt(fm.pid));
    sv({...d,varian:[...d.varian,{id:"V"+String(d.varian.length+100).padStart(3,"0"),pid:parseInt(fm.pid),nama:bibit?bibit.nama.replace("BIBIT ",""):"",uk:fm.uk,ku:fm.ku,hj:parseInt(fm.hj),rb:parseInt(fm.rb)||8,bid:parseInt(fm.bid)||53}]});
    setShow(false);setFm({pid:"",uk:"30ml",ku:"Medium",hj:"",rb:"15",bid:""});};

  return<div>
    <div style={{display:"flex",gap:8,marginBottom:14}}><input value={cari} onChange={e=>setCari(e.target.value)} placeholder="🔍 Cari..." style={{...S.inp,flex:1}}/><button onClick={()=>setShow(true)} style={S.btn1}>+ Tambah Varian</button></div>
    <div style={{fontSize:11,color:"#a09080",marginBottom:12,background:"#faf8f5",padding:"8px 12px",borderRadius:8}}>Total: <b>{Object.keys(gr).length}</b> parfum, <b>{d.varian.length}</b> varian</div>
    {Object.values(gr).map(g=>{if(!g.p)return null;return<K key={g.p.id} s={{marginBottom:10}}>
      <div style={{display:"flex",justifyContent:"space-between",marginBottom:8}}><div><div style={{fontWeight:600,fontSize:13,fontFamily:"'Cormorant Garamond',serif"}}>{g.vs[0]?.nama}</div><div style={{fontSize:10,color:"#a09080"}}>Bibit: {g.p.nama} · Stok: <b style={{color:g.p.stok<=g.p.min?"#c0392b":"#27ae60"}}>{g.p.stok} ml</b></div></div><span style={{fontSize:10,color:"#a09080"}}>{g.vs.length} varian</span></div>
      <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fill,minmax(165px,1fr))",gap:6}}>{g.vs.map(v=><div key={v.id} style={{padding:"8px 10px",background:"#faf8f5",borderRadius:8,display:"flex",justifyContent:"space-between",alignItems:"center"}}>
        <div><div style={{fontSize:11,fontWeight:500}}>{v.uk} · {v.ku}</div><div style={{fontSize:13,fontWeight:700,color:"#d4a574"}}>{rp(v.hj)}</div><div style={{fontSize:9,color:"#a09080"}}>Bibit: {v.rb}ml · HPP: {rp((g.p.beli*v.rb)+(d.produk.find(p=>p.id===v.bid)?.beli||0))}</div></div>
        <button onClick={()=>{if(confirm("Hapus varian?"))sv({...d,varian:d.varian.filter(x=>x.id!==v.id)});}} style={{background:"none",border:"none",color:"#c0392b",cursor:"pointer",fontSize:14}}>✕</button>
      </div>)}</div>
    </K>;})}

    {show&&<Ov onClose={()=>setShow(false)}><div style={{background:"#fff",borderRadius:16,padding:24,width:420}}>
      <h3 style={{margin:"0 0 16px",fontSize:16,fontFamily:"'Cormorant Garamond',serif"}}>Tambah Varian Baru</h3>
      <div style={{display:"flex",flexDirection:"column",gap:10}}>
        <div><label style={S.lbl}>Pilih Bibit</label><select value={fm.pid} onChange={e=>setFm({...fm,pid:e.target.value})} style={S.inp}><option value="">-- Pilih --</option>{d.produk.filter(p=>p.kat==="STOCK PARFUME").map(p=><option key={p.id} value={p.id}>{p.nama} (stok: {p.stok})</option>)}</select></div>
        <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:10}}>
          <div><label style={S.lbl}>Ukuran</label><select value={fm.uk} onChange={e=>setFm({...fm,uk:e.target.value})} style={S.inp}>{UKURAN.map(u=><option key={u}>{u}</option>)}</select></div>
          <div><label style={S.lbl}>Kualitas</label><select value={fm.ku} onChange={e=>setFm({...fm,ku:e.target.value})} style={S.inp}>{KUALITAS.map(k=><option key={k}>{k}</option>)}</select></div>
        </div>
        <div><label style={S.lbl}>Harga Jual (Rp)</label><input type="number" value={fm.hj} onChange={e=>setFm({...fm,hj:e.target.value})} style={S.inp} placeholder="55000"/></div>
        <div><label style={S.lbl}>Jumlah Bibit (ml)</label><input type="number" value={fm.rb} onChange={e=>setFm({...fm,rb:e.target.value})} style={S.inp}/></div>
        <div><label style={S.lbl}>Botol</label><select value={fm.bid} onChange={e=>setFm({...fm,bid:e.target.value})} style={S.inp}><option value="">-- Pilih --</option>{d.produk.filter(p=>p.kat==="STOK BOTOL").map(p=><option key={p.id} value={p.id}>{p.nama} ({rp(p.beli)})</option>)}</select></div>
        <button onClick={simpan} style={S.btn1}>Simpan Varian</button>
      </div>
    </div></Ov>}
  </div>;
}

// ═══════ PENGELUARAN ═══════
function Pengeluaran({d,sv}){
  const[show,setShow]=useState(false);const[fm,setFm]=useState({kat:"Operasional",ket:"",jml:""});
  const tot=d.pengeluaran.reduce((a,p)=>a+p.jml,0);const pk={};d.pengeluaran.forEach(p=>{pk[p.kat]=(pk[p.kat]||0)+p.jml;});
  const simpan=()=>{if(!fm.ket||!fm.jml)return;sv({...d,pengeluaran:[{id:d.pengeluaran.length+1,...fm,jml:parseInt(fm.jml),tgl:new Date().toISOString().slice(0,10)},...d.pengeluaran]});setFm({kat:"Operasional",ket:"",jml:""});setShow(false);};

  return<div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(155px,1fr))",gap:10,marginBottom:14}}>
      <KPI lb="Total Pengeluaran" val={rp(tot)} clr="#c0392b"/>
      {Object.entries(pk).slice(0,3).map(([k,v])=><KPI key={k} lb={k} val={rp(v)} clr="#6b5b4b"/>)}
    </div>
    <J aksi={<button onClick={()=>setShow(!show)} style={S.btn1}>+ Tambah</button>}>Daftar Pengeluaran</J>
    {show&&<K s={{marginBottom:12,border:"2px solid #d4a574"}}>
      <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr auto",gap:10,alignItems:"end"}}>
        <div><label style={S.lbl}>Kategori</label><select value={fm.kat} onChange={e=>setFm({...fm,kat:e.target.value})} style={S.inp}>{KAT_PENG.map(k=><option key={k}>{k}</option>)}</select></div>
        <div><label style={S.lbl}>Keterangan</label><input value={fm.ket} onChange={e=>setFm({...fm,ket:e.target.value})} style={S.inp}/></div>
        <div><label style={S.lbl}>Jumlah (Rp)</label><input type="number" value={fm.jml} onChange={e=>setFm({...fm,jml:e.target.value})} style={S.inp}/></div>
        <button onClick={simpan} style={S.btn1}>Simpan</button>
      </div>
    </K>}
    <T cols={[{l:"Tanggal",c:r=>tgl(r.tgl)},{l:"Kategori",c:r=><L s={r.kat}/>},{l:"Keterangan",c:r=><span style={{fontWeight:500}}>{r.ket}</span>,wrap:true},{l:"Jumlah",r:"right",c:r=><b style={{color:"#c0392b"}}>- {rp(r.jml)}</b>},{l:"",c:r=><button onClick={()=>{if(confirm("Hapus?"))sv({...d,pengeluaran:d.pengeluaran.filter(p=>p.id!==r.id)});}} style={S.btnDel}>Hapus</button>}]} rows={d.pengeluaran}/>
  </div>;
}

// ═══════ LAPORAN (HPP dari BOM!) ═══════
function Laporan({d}){
  const[per,setPer]=useState("bulan");
  const today=new Date().toISOString().slice(0,10);
  const ft=d.transaksi.filter(t=>per==="hari"?t.tgl.startsWith(today):per==="bulan"?t.tgl.startsWith(today.slice(0,7)):true);
  const fp=d.pengeluaran.filter(p=>per==="hari"?p.tgl===today:per==="bulan"?p.tgl.startsWith(today.slice(0,7)):true);
  const pend=ft.reduce((a,t)=>a+t.total,0);
  const hpp=ft.reduce((a,t)=>a+hitungHPP(t.items,d.varian,d.produk),0);
  const tPeng=fp.reduce((a,p)=>a+p.jml,0);const lk=pend-hpp;const lb=lk-tPeng;

  const pm={};ft.forEach(t=>{pm[t.metode]=(pm[t.metode]||0)+t.total;});
  const vs={};ft.forEach(t=>t.items.forEach(i=>{vs[i.vid]=(vs[i.vid]||0)+i.qty;}));
  const top=Object.entries(vs).sort((a,b)=>b[1]-a[1]).slice(0,10).map(([id,qty])=>{const v=d.varian.find(x=>x.id===id);if(!v)return null;const hpp1=hitungHPP([{vid:id,qty:1,hj:v.hj}],d.varian,d.produk);return{nama:`${v.nama} ${v.uk} ${v.ku}`,qty,rev:qty*v.hj,hpp:hpp1*qty,laba:(v.hj-hpp1)*qty};}).filter(Boolean);

  return<div>
    <div style={{display:"flex",gap:5,marginBottom:14}}>{[["hari","Hari Ini"],["bulan","Bulan Ini"],["semua","Semua"]].map(([k,l])=><button key={k} onClick={()=>setPer(k)} style={{padding:"5px 14px",borderRadius:14,border:`1px solid ${per===k?"#d4a574":"#e8e0d8"}`,background:per===k?"#d4a574":"#fff",color:per===k?"#fff":"#6b5b4b",fontSize:10,fontWeight:500,cursor:"pointer"}}>{l}</button>)}</div>

    <J>Laporan Laba Rugi</J>
    <K><div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(140px,1fr))",gap:10}}>
      {[["Pendapatan",pend,"#27ae60"],["HPP (dari Resep)",hpp,"#c0392b"],["Laba Kotor",lk,"#d4a574"],["Pengeluaran",tPeng,"#e67e22"],["Laba Bersih",lb,lb>=0?"#27ae60":"#c0392b"],["Transaksi",ft.length+" nota","#2980b9"]].map(([l,v,w],i)=>
        <div key={i} style={{textAlign:"center",padding:10,background:"#faf8f5",borderRadius:8}}><div style={{fontSize:9,color:"#a09080",textTransform:"uppercase",fontWeight:600}}>{l}</div><div style={{fontSize:17,fontWeight:700,color:w,marginTop:4}}>{typeof v==="number"?rp(v):v}</div></div>
      )}
    </div></K>

    <J>Metode Pembayaran</J>
    <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(140px,1fr))",gap:10}}>{Object.entries(pm).map(([m,v])=><K key={m} s={{textAlign:"center"}}><L s={m}/><div style={{fontSize:18,fontWeight:700,marginTop:6}}>{rp(v)}</div><div style={{fontSize:10,color:"#a09080"}}>{ft.filter(t=>t.metode===m).length} transaksi</div></K>)}</div>

    <J>Produk Terlaris (dengan Laba per Produk)</J>
    <T cols={[{l:"#",c:(_,i)=>i+1},{l:"Produk",c:r=><b style={{fontSize:11}}>{r.nama}</b>,wrap:true},{l:"Terjual",r:"right",c:r=><span>{r.qty} pcs</span>},{l:"Pendapatan",r:"right",c:r=><span>{rp(r.rev)}</span>},{l:"HPP",r:"right",c:r=><span style={{color:"#c0392b"}}>{rp(r.hpp)}</span>},{l:"Laba",r:"right",c:r=><b style={{color:r.laba>=0?"#27ae60":"#c0392b"}}>{rp(r.laba)}</b>}]} rows={top}/>
  </div>;
}

// ═══════ IMPORT / EXPORT ═══════
function ImpExp({d,sv}){
  const[log,setLog]=useState([]);
  const impProduk=async e=>{const f=e.target.files[0];if(!f)return;try{const txt=await f.text();const lines=txt.split("\n").filter(l=>l.trim());const hdr=lines[0].split(/[,\t]/);const ni=hdr.findIndex(h=>h.toLowerCase().includes("name")||h.toLowerCase().includes("nama"));const bi=hdr.findIndex(h=>h.toLowerCase().includes("buy")||h.toLowerCase().includes("beli"));const ki=hdr.findIndex(h=>h.toLowerCase().includes("categ")||h.toLowerCase().includes("kategori"));const si=hdr.findIndex(h=>h.toLowerCase().includes("stock")||h.toLowerCase().includes("stok"));const ai=hdr.findIndex(h=>h.toLowerCase().includes("low_stock")||h.toLowerCase().includes("min"));
    let c=0;const pb=[...d.produk];const mx=Math.max(...pb.map(p=>p.id),0);
    for(let i=1;i<lines.length;i++){const cols=lines[i].split(/[,\t]/);const nama=cols[ni]?.trim();if(!nama)continue;if(pb.find(p=>p.nama.toLowerCase()===nama.toLowerCase()))continue;
      pb.push({id:mx+c+1,nama,kat:cols[ki]?.trim()||"STOCK PARFUME",beli:parseFloat(cols[bi])||900,stok:parseInt(cols[si])||0,min:parseInt(cols[ai])||50,sat:nama.includes("BOTOL")?"pcs":"ml"});c++;}
    sv({...d,produk:pb});setLog(p=>[`✅ ${c} produk baru diimport`,...p]);}catch(err){setLog(p=>[`❌ Gagal: ${err.message}`,...p]);}e.target.value="";};

  const expJSON=()=>{const b=new Blob([JSON.stringify(d,null,2)],{type:"application/json"});const a=document.createElement("a");a.href=URL.createObjectURL(b);a.download=`ks_parfume_backup_${new Date().toISOString().slice(0,10)}.json`;a.click();setLog(p=>["✅ Data di-export (JSON)",...p]);};
  const expCSV=()=>{let csv="No,Tanggal,Kasir,Total,Diskon,Metode,HPP,Laba\n";d.transaksi.forEach(t=>{const hpp=hitungHPP(t.items,d.varian,d.produk);csv+=`${t.id},${t.tgl},${t.user},${t.total},${t.disk},${t.metode},${hpp},${t.total-hpp}\n`;});const b=new Blob([csv],{type:"text/csv"});const a=document.createElement("a");a.href=URL.createObjectURL(b);a.download=`laporan_${new Date().toISOString().slice(0,10)}.csv`;a.click();setLog(p=>["✅ Laporan di-export (CSV)",...p]);};

  return<div>
    <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:14,marginBottom:20}}>
      <K><div style={{fontSize:13,fontWeight:600,marginBottom:10,fontFamily:"'Cormorant Garamond',serif"}}>📥 Import Data</div>
        <div style={{fontSize:11,fontWeight:500,marginBottom:4}}>Upload Produk (CSV/TXT)</div>
        <div style={{fontSize:10,color:"#a09080",marginBottom:8}}>Kolom: name, buy_price, category, stock_qty, low_stock_alert<br/>Simpan file Excel Olsera ke CSV dulu.</div>
        <input type="file" accept=".csv,.txt,.tsv" onChange={impProduk} style={{fontSize:11}}/>
      </K>
      <K><div style={{fontSize:13,fontWeight:600,marginBottom:10,fontFamily:"'Cormorant Garamond',serif"}}>📤 Export Data</div>
        <div style={{display:"flex",flexDirection:"column",gap:8}}>
          <button onClick={expJSON} style={S.btn1}>Export Semua (JSON)</button>
          <button onClick={expCSV} style={{...S.btn1,background:"#2980b9"}}>Export Transaksi + HPP (CSV)</button>
        </div>
      </K>
    </div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(140px,1fr))",gap:10,marginBottom:16}}>
      <KPI lb="Produk" val={d.produk.length}/><KPI lb="Varian" val={d.varian.length}/><KPI lb="Transaksi" val={d.transaksi.length}/><KPI lb="Pergerakan" val={d.movement.length}/>
    </div>
    {log.length>0&&<><J>Log</J><K s={{background:"#faf8f5"}}>{log.map((l,i)=><div key={i} style={{fontSize:11,padding:"4px 0",borderBottom:"1px solid #f0ebe4",color:l.startsWith("✅")?"#27ae60":"#c0392b"}}>{l}</div>)}</K></>}
  </div>;
}

// ═══════ PENGATURAN ═══════
function Pengaturan({d,sv}){
  const[fm,setFm]=useState(d.set);const[uf,setUf]=useState({nama:"",pin:"",peran:"kasir"});const[show,setShow]=useState(false);
  const tu=()=>{if(!uf.nama||uf.pin.length!==4){alert("Nama & PIN 4 digit wajib!");return;}sv({...d,users:[...d.users,{id:d.users.length+1,...uf}]});setUf({nama:"",pin:"",peran:"kasir"});setShow(false);};

  return<div>
    <J>Informasi Usaha</J>
    <K><div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:10}}>
      <div><label style={S.lbl}>Nama Usaha</label><input value={fm.nama} onChange={e=>setFm({...fm,nama:e.target.value})} style={S.inp}/></div>
      <div><label style={S.lbl}>Alamat</label><input value={fm.alamat} onChange={e=>setFm({...fm,alamat:e.target.value})} style={S.inp}/></div>
      <div><label style={S.lbl}>Telepon</label><input value={fm.telp||""} onChange={e=>setFm({...fm,telp:e.target.value})} style={S.inp}/></div>
    </div><button onClick={()=>sv({...d,set:fm})} style={{...S.btn1,marginTop:12}}>Simpan</button></K>

    <J aksi={<button onClick={()=>setShow(!show)} style={S.btn1}>+ Tambah User</button>}>Kelola Pengguna</J>
    {show&&<K s={{marginBottom:12,border:"2px solid #d4a574"}}><div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr auto",gap:10,alignItems:"end"}}>
      <div><label style={S.lbl}>Nama</label><input value={uf.nama} onChange={e=>setUf({...uf,nama:e.target.value})} style={S.inp}/></div>
      <div><label style={S.lbl}>PIN (4 digit)</label><input value={uf.pin} onChange={e=>setUf({...uf,pin:e.target.value.slice(0,4)})} maxLength={4} style={S.inp}/></div>
      <div><label style={S.lbl}>Peran</label><select value={uf.peran} onChange={e=>setUf({...uf,peran:e.target.value})} style={S.inp}><option value="kasir">Kasir</option><option value="owner">Owner</option></select></div>
      <button onClick={tu} style={S.btn1}>Simpan</button>
    </div></K>}
    <T cols={[{l:"Nama",c:r=><b>{r.nama}</b>},{l:"PIN",c:r=><span style={{fontFamily:"monospace",background:"#faf8f5",padding:"2px 8px",borderRadius:4}}>{r.pin}</span>},{l:"Peran",c:r=><L s={r.peran}/>},{l:"",c:r=>r.peran!=="owner"?<button onClick={()=>{if(confirm("Hapus user?"))sv({...d,users:d.users.filter(u=>u.id!==r.id)});}} style={S.btnDel}>Hapus</button>:null}]} rows={d.users}/>

    <J>Info Sistem</J>
    <K s={{background:"#faf8f5"}}>{[["Versi","KS Parfume ERP v3 Final"],["Database","Lokal (Offline)"],["HPP","Otomatis dari Resep/BOM"],["Backup","Google Drive"],["Update","28 Maret 2026"]].map(([k,v],i)=><div key={i} style={{display:"flex",justifyContent:"space-between",padding:"6px 0",borderBottom:"1px solid #f0ebe4",fontSize:12}}><span style={{color:"#a09080"}}>{k}</span><span style={{fontWeight:500}}>{v}</span></div>)}</K>
  </div>;
}
