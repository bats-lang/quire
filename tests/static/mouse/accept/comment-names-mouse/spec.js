// page.mouse.click() is made only through rawMouse
/* const {mouse} = page; is not a use */
await rawMouse(page, "click", 10, 20);
