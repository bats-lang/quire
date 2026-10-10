// Small EPUBs that declare their protection (quire#427): Adobe ADEPT,
// Readium LCP, Apple FairPlay, Kobo, an algorithm nobody knows; and
// the two that are not refused, a book whose fonts are only obfuscated
// and a book that is damaged and declares nothing. Each is checked by
// epubcheck (e2e/epubcheck.spec.js): `valid` ones must pass it; an
// invalid one is invalid on purpose, and `errors` names the only
// messages it may give. The chapters of a protected book are random
// bytes, as an encrypted chapter's are.

import { encryptionXml, randomBytes } from './create-epub.js';

export const AES128 = 'http://www.w3.org/2001/04/xmlenc#aes128-cbc';
export const AES256 = 'http://www.w3.org/2001/04/xmlenc#aes256-cbc';
export const IDPF_FONTS = 'http://www.idpf.org/2008/embedding';
export const ADOBE_FONTS = 'http://ns.adobe.com/pdf/enc#RC';

const chapterUris = [1, 2, 3].map(k => `OEBPS/chapter${k}.xhtml`);
const over = algorithm => chapterUris.map(uri => ({ uri, algorithm }));

const adeptKey = '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><adept:resource xmlns:adept="http://ns.adobe.com/adept">urn:uuid:00000000-0000-4000-8000-000000000001</adept:resource></ds:KeyInfo>';
const lcpKey = '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:RetrievalMethod URI="license.lcpl#/encryption/content_key" Type="http://readium.org/2014/01/lcp#EncryptedContentKey"/></ds:KeyInfo>';

const rightsXml = `<?xml version="1.0"?>
<adept:rights xmlns:adept="http://ns.adobe.com/adept">
  <adept:licenseToken><adept:resource>urn:uuid:00000000-0000-4000-8000-000000000001</adept:resource></adept:licenseToken>
</adept:rights>`;

const licenseLcpl = JSON.stringify({
  id: '00000000-0000-4000-8000-000000000002', issued: '2026-01-01T00:00:00Z', provider: 'https://lcp.example.test',
  encryption: {
    profile: 'http://readium.org/lcp/basic-profile',
    content_key: { algorithm: AES256, encrypted_value: 'AAAA' },
    user_key: { algorithm: 'http://www.w3.org/2001/04/xmlenc#sha256', text_hint: 'The passphrase', key_check: 'AAAA' },
  },
  links: [{ rel: 'hint', href: 'https://lcp.example.test/hint' }],
  signature: { algorithm: 'http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256', certificate: 'AAAA', value: 'AAAA' },
});

const sinfXml = `<?xml version="1.0" encoding="UTF-8"?>
<fairplay xmlns="http://ns.apple.com/fairplay"><sinf>AAAA</sinf></fairplay>`;

const base = { author: 'Protected', encryptedChapters: true };

export const drmBooks = {
  /** ADEPT: rights.xml, and an encryption.xml with AES over every chapter */
  adept: { valid: true, opts: { ...base, title: 'Adept Book', metaInf: [
    { name: 'rights.xml', data: rightsXml },
    { name: 'encryption.xml', data: encryptionXml(over(AES128), { keyInfo: adeptKey }) }] } },

  /** ADEPT told by the encryption.xml alone (its namespace), no rights.xml */
  adeptEncryptionOnly: { valid: true, opts: { ...base, title: 'Adept Namespace Book', metaInf: [
    { name: 'encryption.xml', data: encryptionXml(over(AES128), { keyInfo: adeptKey }) }] } },

  /** LCP: a license.lcpl, and an encryption.xml that takes its key from it */
  lcp: { valid: true, opts: { ...base, title: 'Lcp Book', metaInf: [
    { name: 'license.lcpl', data: licenseLcpl },
    { name: 'encryption.xml', data: encryptionXml(over(AES256), { keyInfo: lcpKey }) }] } },

  /** LCP told by the licence alone: its chapters are ciphertext that no
      encryption.xml names, so epubcheck cannot parse them (invalid as intended) */
  lcpLicenseOnly: { valid: false, errors: ['RSC-016'], opts: { ...base, title: 'Lcp Licence Book', metaInf: [
    { name: 'license.lcpl', data: licenseLcpl }] } },

  /** FairPlay: a sinf.xml, with chapters in AES */
  fairPlay: { valid: true, opts: { ...base, title: 'FairPlay Book', metaInf: [
    { name: 'sinf.xml', data: sinfXml },
    { name: 'encryption.xml', data: encryptionXml(over(AES128)) }] } },

  /** Kobo: kobo.com in the encryption.xml's namespaces */
  kobo: { valid: true, opts: { ...base, title: 'Kobo Book', metaInf: [
    { name: 'encryption.xml', data: encryptionXml(over(AES128), { namespaces: ' xmlns:kobo="http://www.kobo.com/ns/drm"' }) }] } },

  /** An encryption.xml that names an algorithm nobody knows over the chapters, and no scheme */
  unknownAlgorithm: { valid: true, opts: { ...base, title: 'Unknown Algorithm Book', metaInf: [
    { name: 'encryption.xml', data: encryptionXml(over('urn:example:cipher:rot13')) }] } },

  /** Only its fonts are obfuscated, by the two algorithms of the EPUB
      and Adobe, and its chapters are plain: not DRM */
  obfuscatedFonts: { valid: true, opts: {
    title: 'Obfuscated Fonts Book', author: 'Protected',
    extraFiles: [
      { name: 'fonts/first.otf', data: randomBytes(2048, 7), mediaType: 'font/otf', store: true },
      { name: 'fonts/second.otf', data: randomBytes(2048, 8), mediaType: 'font/otf', store: true }],
    metaInf: [{ name: 'encryption.xml', data: encryptionXml([
      { uri: 'OEBPS/fonts/first.otf', algorithm: IDPF_FONTS },
      { uri: 'OEBPS/fonts/second.otf', algorithm: ADOBE_FONTS }]) }] } },

  /** Damaged (its package cannot be read) and declaring nothing: damaged, never DRM */
  damagedPackage: { valid: false, errors: ['OPF-001', 'PKG-008'], opts: { title: 'Damaged Package Book', author: 'Protected', damagedPackage: true } },
};
