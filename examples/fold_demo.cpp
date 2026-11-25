// 用于验证 Vim 语法折叠：namespace、class、function、if、for、switch
#include <iostream>
#include <string>
#include <vector>

namespace folddemo {

class Item {
public:
    Item(int id, std::string name) : id_(id), name_(std::move(name)) {}

    std::string label() const {
        switch (id_ % 3) {
        case 0:
            return name_ + ": %3 == 0";
        case 1:
            return name_ + ": %3 == 1";
        default:
            return name_ + ": %3 == 2";
        }
    }

private:
    int id_;
    std::string name_;
};

int sum_even(const std::vector<int> &values) {
    int total = 0;

    for (int value : values) {
        if (value % 2 != 0) {
            continue;
        }

        total += value;
    }

    return total;
}

void print_items(const std::vector<Item> &items) {
    for (const auto &item : items) {
        std::cout << item.label() << '\n';
    }
}

}  // namespace folddemo

int main() {
    std::vector<int> values{1, 2, 3, 4, 5, 6, 7, 8};
    std::vector<folddemo::Item> items{
        {1, "alpha"},
        {2, "beta"},
        {3, "gamma"},
    };

    std::cout << "sum of even values: " << folddemo::sum_even(values) << '\n';
    folddemo::print_items(items);

    return 0;
}
