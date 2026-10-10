// EPUB 3 books with audio and video elements in a chapter (#424), checked
// by epubcheck (e2e/epubcheck.spec.js). The media files are a few bytes
// of the right type: epubcheck checks the type, not the stream.

const bytes = n => Buffer.alloc(n, 7);

export const mediaBooks = {
  media: { valid: true, opts: {
    title: 'Media', author: 'Media', toc: [{ label: 'Media', href: 'chapter1.xhtml' }],
    extraFiles: [
      { name: 'audio/clip.mp3', mediaType: 'audio/mpeg', data: bytes(64), store: true },
      { name: 'audio/clip.m4a', mediaType: 'audio/mp4', data: bytes(64), store: true },
      { name: 'video/clip.mp4', mediaType: 'video/mp4', data: bytes(64), store: true },
    ],
    rawChapters: [{ body:
      '<h1>Media</h1>\n' +
      '<p>Before the audio.</p>\n' +
      '<audio id="withtext" controls="controls" src="audio/clip.mp3">Fallback words for the audio.</audio>\n' +
      '<audio id="sources" controls="controls"><source src="audio/clip.mp3" type="audio/mpeg"/><source src="audio/clip.m4a" type="audio/mp4"/></audio>\n' +
      '<video id="movie" controls="controls" width="640" height="360" src="video/clip.mp4">Fallback words for the video.</video>\n' +
      '<p>After the media.</p>' }] } },
};
