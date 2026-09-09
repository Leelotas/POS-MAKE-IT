'use client';
import {useEffect,useState} from 'react';
import {rpc} from '@/lib/supabase';
export function AdminLink(){const[show,setShow]=useState(false);useEffect(()=>{let live=true;rpc<boolean>('makeit_is_admin').then(v=>{if(live)setShow(v)}).catch(()=>{});return()=>{live=false}},[]);return show?<a className="btn secondary" href="/admin">จัดการระบบ Admin</a>:null}
