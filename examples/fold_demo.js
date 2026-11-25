// 用于验证 Vim 缩进折叠：class、function、if、for、while、switch

class Item {
  constructor(id, name) {
    this.id = id;
    this.name = name;
  }

  label() {
    switch (this.id % 3) {
      case 0:
        return `${this.name}: %3 === 0`;
      case 1:
        return `${this.name}: %3 === 1`;
      default:
        return `${this.name}: %3 === 2`;
    }
  }
}

function sumEven(values) {
  let total = 0;

  for (let i = 0; i < values.length; i++) {
    if (values[i] % 2 !== 0) {
      continue;
    }

    total += values[i];
  }

  return total;
}

function printItems(items) {
  let index = 0;

  while (index < items.length) {
    try {
      console.log(items[index].label());
    } catch (error) {
      console.error('invalid item:', error.message);
    } finally {
      index += 1;
    }
  }
}

const values = [1, 2, 3, 4, 5, 6, 7, 8];
const items = [
  new Item(1, 'alpha'),
  new Item(2, 'beta'),
  new Item(3, 'gamma'),
];

console.log('sum of even values:', sumEven(values));
printItems(items);
