const note = 'page.mouse.down()';
const other = "const {mouse} = page";
const template = `see page.mouse and ${label}`;
expect(note).toContain('.mouse');
