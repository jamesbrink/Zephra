import chapter from '../_content/settings.json';
import GuideArticle from '../guide-article';
import { chapterMetadata } from '../guide-metadata';

export const metadata = chapterMetadata(chapter);
export default function Page() { return <GuideArticle chapter={chapter} />; }
