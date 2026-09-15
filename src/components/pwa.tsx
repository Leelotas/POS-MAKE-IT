'use client';

import {useEffect,useState} from 'react';
import {CheckCircle2,Download,Share2,Smartphone} from 'lucide-react';

type InstallPromptEvent=Event&{
 prompt:()=>Promise<void>;
 userChoice:Promise<{outcome:'accepted'|'dismissed'}>;
};

declare global {
 interface WindowEventMap { beforeinstallprompt: InstallPromptEvent }
 interface Navigator { standalone?: boolean }
}

const isStandalone=()=>typeof window!=='undefined'&&(window.matchMedia('(display-mode: standalone)').matches||navigator.standalone===true);

export function PwaRegister(){
 useEffect(()=>{if('serviceWorker'in navigator)void navigator.serviceWorker.register('/sw.js').catch(()=>{})},[]);
 return null;
}

export function InstallApp(){
 const[prompt,setPrompt]=useState<InstallPromptEvent|null>(null),[installed,setInstalled]=useState(false),[showHelp,setShowHelp]=useState(false),[ios,setIos]=useState(false);
 useEffect(()=>{
  setInstalled(isStandalone());setIos(/iphone|ipad|ipod/i.test(navigator.userAgent));
  const ready=(event:InstallPromptEvent)=>{event.preventDefault();setPrompt(event)};
  const done=()=>{setInstalled(true);setPrompt(null);setShowHelp(false)};
  window.addEventListener('beforeinstallprompt',ready);window.addEventListener('appinstalled',done);
  return()=>{window.removeEventListener('beforeinstallprompt',ready);window.removeEventListener('appinstalled',done)};
 },[]);
 async function install(){
  if(!prompt){setShowHelp(v=>!v);return}
  await prompt.prompt();const choice=await prompt.userChoice;if(choice.outcome==='accepted')setInstalled(true);setPrompt(null);
 }
 if(installed)return <div className="pwa-installed"><CheckCircle2 size={19}/><div><strong>ติดตั้ง MAKE IT แล้ว</strong><small>เปิดจากไอคอนบนหน้าจอโฮมได้เลย</small></div></div>;
 return <section className="pwa-install"><span className="pwa-install-icon"><Smartphone size={23}/></span><div><strong>ติดตั้ง MAKE IT บนมือถือ</strong><small>เปิดร้านได้เร็วเหมือนแอปทั่วไป</small></div><button type="button" className="btn primary" onClick={install}><Download size={17}/>{prompt?'ติดตั้งแอป':'วิธีติดตั้ง'}</button>{showHelp&&<p><Share2 size={16}/>{ios?'กดปุ่มแชร์ของ Safari แล้วเลือก “เพิ่มไปยังหน้าจอโฮม”':'เปิดเมนูเบราว์เซอร์ แล้วเลือก “ติดตั้งแอป” หรือ “เพิ่มไปยังหน้าจอหลัก”'}</p>}</section>;
}
