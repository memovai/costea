import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Link from "next/link";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Costea — Cost Prediction for AI Agents",
  description:
    "Track, analyze, and estimate token consumption across Claude Code, Codex CLI, and OpenClaw.",
};

function Nav() {
  return (
    <nav className="border-b border-border px-6 py-4 flex items-center justify-between bg-surface/80 backdrop-blur-sm sticky top-0 z-50">
      <Link href="/" className="flex items-center gap-2 font-bold text-lg tracking-wider">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/mascot.png" alt="" width={28} height={28} className="rounded" />
        COSTEA
      </Link>
      <div className="flex items-center gap-6 text-sm">
        <Link href="/dashboard" className="hover:text-muted transition-colors">
          Dashboard
        </Link>
        <Link href="/estimate" className="hover:text-muted transition-colors">
          Estimate
        </Link>
        <Link href="/analytics" className="hover:text-muted transition-colors">
          Analytics
        </Link>
        <Link href="/accuracy" className="hover:text-muted transition-colors">
          Accuracy
        </Link>
        <a
          href="https://github.com/memovai/costea"
          target="_blank"
          rel="noopener noreferrer"
          className="px-3 py-1.5 bg-accent text-surface rounded text-xs font-medium hover:opacity-80 transition-opacity"
        >
          GitHub
        </a>
      </div>
    </nav>
  );
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <Nav />
        <main className="flex-1">{children}</main>
        <footer className="border-t border-border px-6 py-6 flex flex-col items-center gap-2 text-xs text-muted-light">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/mascot.png" alt="Costea Owl" width={40} height={40} className="opacity-40" />
          <span>Costea &mdash; Know what you spend before you spend it.</span>
        </footer>
      </body>
    </html>
  );
}
