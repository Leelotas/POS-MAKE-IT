'use client';
import {useEffect,useRef,useState} from 'react';
import {X,ImageIcon,LoaderCircle,Camera,Upload} from 'lucide-react';
import {signedImage} from '@/lib/supabase';
export function Logo({large=false}:{large?:boolean}){return <div className={`logo ${large?'large':''}`}><img src="/logo.png" alt="MAKE IT Mobile POS System"/></div>}
export function Photo({path,name}:{path:string|null;name:string}){
 const [url,setUrl]=useState('');useEffect(()=>{let alive=true;setUrl('');if(path)signedImage(path).then(u=>{if(alive)setUrl(u)}).catch(()=>{});return()=>{alive=false}},[path]);
 return url?<img className="product-photo" src={url} alt={name}/>:<div className="product-placeholder"><ImageIcon size={30}/></div>;
}
export function Evidence({path}:{path:string}){const[url,setUrl]=useState('');const[error,setError]=useState(false);useEffect(()=>{signedImage(path).then(setUrl).catch(()=>setError(true))},[path]);return url?<a href={url} target="_blank" rel="noreferrer"><img className="evidence" src={url} alt="หลักฐานประกอบรายการ"/></a>:<p>{error?'เปิดภาพไม่สำเร็จ กรุณาปิดแล้วลองใหม่':'กำลังเปิดภาพ…'}</p>}
export function Modal({title,children,onClose}:{title:string;children:React.ReactNode;onClose:()=>void}){
 const ref=useRef<HTMLDialogElement>(null);
 useEffect(()=>{ref.current?.showModal();const el=ref.current;return()=>el?.close()},[]);
 return <dialog ref={ref} className="modal" onCancel={e=>{e.preventDefault();onClose()}}><div className="modal-head"><h2>{title}</h2><button className="icon-btn" onClick={onClose} aria-label="ปิด"><X/></button></div><div className="modal-body">{children}</div></dialog>;
}
export function Submit({busy,children}:{busy:boolean;children:React.ReactNode}){return <button className="btn primary full" type="submit" disabled={busy}>{busy?<><LoaderCircle className="spin" size={18}/>กำลังบันทึก…</>:children}</button>}
export function FileField({label,onChange,required=false,disabled=false}:{label:string;onChange:(f:File|null)=>void;required?:boolean;disabled?:boolean}){
 const[file,setFile]=useState<File|null>(null);const[url,setUrl]=useState('');
 useEffect(()=>{if(!file){setUrl('');return}const u=URL.createObjectURL(file);setUrl(u);return()=>URL.revokeObjectURL(u)},[file]);
 function change(e:React.ChangeEvent<HTMLInputElement>){const f=e.target.files?.[0]??null;setFile(f);onChange(f)}
 return <div className="file-field"><span className="field-title">{label}{required?' *':''}</span><div className="upload-actions"><label className="btn soft"><Camera size={18}/>ถ่ายรูป<input type="file" accept="image/jpeg,image/png,image/webp" capture="environment" onChange={change} disabled={disabled}/></label><label className="btn secondary"><Upload size={18}/>เลือกภาพ<input type="file" accept="image/jpeg,image/png,image/webp" onChange={change} disabled={disabled}/></label></div>{url&&<img className="upload-preview" src={url} alt="ภาพที่เลือก"/>}<small>{file?.name??'JPG, PNG หรือ WebP ขนาดไม่เกิน 10 MB'}</small></div>
}
export function Empty({title,detail,children}:{title:string;detail:string;children?:React.ReactNode}){return <div className="empty"><span className="empty-icon"><ImageIcon size={30}/></span><h3>{title}</h3><p>{detail}</p>{children}</div>}
export const errorText=(e:unknown)=>e instanceof Error?e.message:'ไม่สามารถทำรายการได้ กรุณาลองใหม่';
