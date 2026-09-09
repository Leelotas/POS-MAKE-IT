import type { Metadata, Viewport } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'MAKE IT — ร้านของคุณ จัดการได้ในมือ',
  description: 'ขายสินค้า จัดการสต็อก และดูรายรับรายจ่ายของร้านในที่เดียว',
  manifest: '/manifest.webmanifest',
  appleWebApp: { capable: true, title: 'MAKE IT', statusBarStyle: 'default' },
  icons: { icon: '/icon.svg', apple: '/logo.png' },
};
export const viewport: Viewport = { width: 'device-width', initialScale: 1, themeColor: '#165dff' };
export default function RootLayout({children}: Readonly<{children: React.ReactNode}>) {
  return <html lang="th"><body>{children}</body></html>;
}
