// Regenerates the PNG app icons from scripts/icon-source.svg.
import sharp from 'sharp'
import { readFileSync } from 'node:fs'

const svg = readFileSync(new URL('./icon-source.svg', import.meta.url))
const out = (name) => new URL(`../public/${name}`, import.meta.url).pathname

await sharp(svg).resize(192, 192).png().toFile(out('icon-192.png'))
await sharp(svg).resize(512, 512).png().toFile(out('icon-512.png'))
await sharp(svg).resize(180, 180).flatten({ background: '#d9480f' }).png().toFile(out('apple-touch-icon.png'))
// Maskable: full-bleed background with the glyph inside the 80% safe zone.
const inner = await sharp(svg).resize(400, 400).png().toBuffer()
await sharp({ create: { width: 512, height: 512, channels: 4, background: '#d9480f' } })
  .composite([{ input: inner, gravity: 'centre' }])
  .png()
  .toFile(out('icon-512-maskable.png'))
console.log('icons written')
