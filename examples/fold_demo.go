// 用于验证 Vim 语法折叠：struct、func、if、for、switch
package main

import "fmt"

const maxItems = 8

type Item struct {
	ID   int
	Name string
}

func (i Item) Label() string {
	switch i.ID % 3 {
	case 0:
		return fmt.Sprintf("%s: %%3 == 0", i.Name)
	case 1:
		return fmt.Sprintf("%s: %%3 == 1", i.Name)
	default:
		return fmt.Sprintf("%s: %%3 == 2", i.Name)
	}
}

func sumEven(values []int) int {
	total := 0

	for _, value := range values {
		if value%2 != 0 {
			continue
		}

		total += value
	}

	return total
}

func printItems(items []Item) {
	for index, item := range items {
		if item.ID < 0 {
			continue
		}

		fmt.Printf("[%d] %s\n", index, item.Label())
	}
}

func main() {
	values := []int{1, 2, 3, 4, 5, 6, 7, 8}
	items := []Item{
		{ID: 1, Name: "alpha"},
		{ID: 2, Name: "beta"},
		{ID: 3, Name: "gamma"},
	}

	fmt.Println("sum of even values:", sumEven(values))
	printItems(items)
}
