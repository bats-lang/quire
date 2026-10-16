await page.mouse.move(10, 20);
await page.mouse.down();
await page.mouse.move(80, 20, { steps: 5 });
await page.mouse.up();
