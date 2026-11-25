// 用于验证 Vim 语法折叠：class、method、if、for、switch

public class FoldDemo {
    private static final int MAX_ITEMS = 8;

    private static final class Item {
        private final int id;
        private final String name;

        Item(int id, String name) {
            this.id = id;
            this.name = name;
        }

        String label() {
            switch (id % 3) {
                case 0:
                    return name + ": %3 == 0";
                case 1:
                    return name + ": %3 == 1";
                default:
                    return name + ": %3 == 2";
            }
        }
    }

    private static int sumEven(int[] values) {
        int total = 0;

        for (int value : values) {
            if (value % 2 != 0) {
                continue;
            }

            total += value;
        }

        return total;
    }

    private static void printItems(Item[] items) {
        for (int i = 0; i < items.length; i++) {
            if (items[i] == null) {
                continue;
            }

            System.out.println(items[i].label());
        }
    }

    public static void main(String[] args) {
        int[] values = {1, 2, 3, 4, 5, 6, 7, 8};
        Item[] items = {
            new Item(1, "alpha"),
            new Item(2, "beta"),
            new Item(3, "gamma"),
        };

        System.out.println("sum of even values: " + sumEven(values));
        printItems(items);
    }
}
