// Снимает демо-ролик и иконку Hatch из HTML-макетов этой папки.
//   npm i --no-save playwright && npx playwright install chromium
//   node docs/demo/record.js
// Результат: docs/media/demo.mp4, docs/media/demo.gif, docs/media/icon-1024.png (нужен ffmpeg).
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const here = __dirname;
const media = path.join(here, '..', 'media');
const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'hatch-demo-'));

(async () => {
  const browser = await chromium.launch();

  const icon = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  await icon.goto('file://' + path.join(here, 'icon.html'));
  await icon.screenshot({ path: path.join(media, 'icon-1024.png'), omitBackground: true });

  const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 }, recordVideo: { dir: tmp, size: { width: 1600, height: 900 } } });
  const page = await ctx.newPage();
  await page.goto('file://' + path.join(here, 'hatch-demo.html') + '?rec');
  await page.waitForFunction(() => window.__done === true, null, { timeout: 120000 });
  await page.waitForTimeout(300);
  const video = await page.video().path();
  await ctx.close();
  await browser.close();

  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-ss', '0.4', '-i', video, '-c:v', 'libx264', '-preset', 'slow', '-crf', '18',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', path.join(media, 'demo.mp4')]);
  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-ss', '0.4', '-i', video, '-vf',
    // ролик длинный: GIF реже и меньше, чтобы README открывался быстро; качество — в MP4
    'fps=8,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle',
    path.join(media, 'demo.gif')]);
  console.log('готово:', media);
})();
