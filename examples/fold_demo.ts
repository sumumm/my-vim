// 用于验证 Vim 缩进折叠：interface、class、if、for、switch

interface Item {
  id: number;
  name: string;
}

class ItemList {
  private items: Item[];

  constructor(items: Item[]) {
    this.items = items;
  }

  label(item: Item): string {
    switch (item.id % 3) {
      case 0:
        return `${item.name}: %3 === 0`;
      case 1:
        return `${item.name}: %3 === 1`;
      default:
        return `${item.name}: %3 === 2`;
    }
  }

  printAll(): void {
    for (const item of this.items) {
      if (item.id < 0) {
        continue;
      }

      console.log(this.label(item));
    }
  }
}

function sumEven(values: number[]): number {
  let total = 0;

  for (let i = 0; i < values.length; i++) {
    if (values[i] % 2 !== 0) {
      continue;
    }

    total += values[i];
  }

  return total;
}

const values: number[] = [1, 2, 3, 4, 5, 6, 7, 8];
const items: Item[] = [
  { id: 1, name: 'alpha' },
  { id: 2, name: 'beta' },
  { id: 3, name: 'gamma' },
];

console.log('sum of even values:', sumEven(values));
new ItemList(items).printAll();
