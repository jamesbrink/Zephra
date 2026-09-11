import GuideShell from './guide-shell';
import './guide.css';
export default function GuideLayout({ children }: { children: React.ReactNode }) {
  return <GuideShell>{children}</GuideShell>;
}
