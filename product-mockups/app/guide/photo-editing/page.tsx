import chapter from '../_content/photo-editing.json';
import GuideArticle from '../guide-article';
import { chapterMetadata } from '../guide-metadata';

export const metadata = chapterMetadata(chapter);
export default function Page() { return <GuideArticle chapter={chapter} />; }
