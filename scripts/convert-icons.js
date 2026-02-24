const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const sizes = [16, 32, 48, 64, 128, 256, 512];
const inputSvg = path.join(__dirname, '..', 'docs', 'digilab-icon.svg');
const faviconSvg = path.join(__dirname, '..', 'docs', 'favicon.svg');
const outputDir = path.join(__dirname, '..', 'docs', 'icons');
const wwwDir = path.join(__dirname, '..', 'www');

// Create output directory if it doesn't exist
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

async function convertToPng() {
  const svgBuffer = fs.readFileSync(inputSvg);

  for (const size of sizes) {
    const outputPath = path.join(outputDir, `digilab-icon-${size}.png`);

    await sharp(svgBuffer)
      .resize(size, size)
      .png()
      .toFile(outputPath);

    console.log(`Created: ${outputPath}`);
  }

  // Also create a copy without size suffix for the largest one (for social media)
  const socialPath = path.join(outputDir, 'digilab-icon.png');
  await sharp(svgBuffer)
    .resize(512, 512)
    .png()
    .toFile(socialPath);
  console.log(`Created: ${socialPath}`);

  // Generate favicon PNGs from favicon.svg
  const faviconBuffer = fs.readFileSync(faviconSvg);

  // Create 32x32 PNG for favicon (modern browsers)
  const favicon32Path = path.join(wwwDir, 'favicon-32x32.png');
  await sharp(faviconBuffer)
    .resize(32, 32)
    .png()
    .toFile(favicon32Path);
  console.log(`Created: ${favicon32Path}`);

  // Create 16x16 PNG for favicon
  const favicon16Path = path.join(wwwDir, 'favicon-16x16.png');
  await sharp(faviconBuffer)
    .resize(16, 16)
    .png()
    .toFile(favicon16Path);
  console.log(`Created: ${favicon16Path}`);

  // Create apple-touch-icon (180x180)
  const appleTouchPath = path.join(wwwDir, 'apple-touch-icon.png');
  await sharp(svgBuffer)  // Use the full icon for apple touch
    .resize(180, 180)
    .png()
    .toFile(appleTouchPath);
  console.log(`Created: ${appleTouchPath}`);

  // Generate favicon.ico from the PNG files using CLI
  const icoPath = path.join(wwwDir, 'favicon.ico');
  execSync(`npx png-to-ico "${favicon16Path}" "${favicon32Path}" > "${icoPath}"`, { shell: true });
  console.log(`Created: ${icoPath}`);

  console.log('\nAll icons generated successfully!');
}

convertToPng().catch(console.error);
