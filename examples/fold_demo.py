"""用于验证 Vim 缩进折叠：class、def、if、for、while、try。"""

MAX_ITEMS = 8


class Item:
    def __init__(self, item_id, name):
        self.item_id = item_id
        self.name = name

    def label(self):
        if self.item_id % 3 == 0:
            return f"{self.name}: %3 == 0"
        elif self.item_id % 3 == 1:
            return f"{self.name}: %3 == 1"
        else:
            return f"{self.name}: %3 == 2"


def sum_even(values):
    total = 0

    for value in values:
        if value % 2 != 0:
            continue

        total += value

    return total


def print_items(items):
    index = 0

    while index < len(items):
        try:
            print(items[index].label())
        except AttributeError:
            print(f"invalid item: {items[index]!r}")
        finally:
            index += 1


def main():
    values = [1, 2, 3, 4, 5, 6, 7, 8]
    items = [
        Item(item_id, name)
        for item_id, name in enumerate(["alpha", "beta", "gamma"], start=1)
    ]

    print("sum of even values:", sum_even(values))
    print_items(items)


if __name__ == "__main__":
    main()
