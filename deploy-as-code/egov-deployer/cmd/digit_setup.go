package main

import (
	"bytes"
	"container/list"
	"flag"
	"fmt"
	"io/ioutil"
	"os/exec"
	"strings"

	"gopkg.in/yaml.v2"
)

//Defining a struct to parse the yaml file

type Digit struct {
	Version string `yaml:"version"`
	Modules []struct {
		Name         string   `yaml:"name"`
		Services     []string `yaml:"services"`
		Dependencies []string `yaml:"dependencies,omitempty"`
	} `yaml:"modules"`
}

type Set struct {
	set map[string]bool
}

func NewSet() *Set {
	return &Set{make(map[string]bool)}
}
func (set *Set) Add(i string) bool {
	_, found := set.set[i]
	set.set[i] = true
	return !found //False if it existed already
}
func (set *Set) Get(i string) bool {
	_, found := set.set[i]
	return found
}

func main() {
	//Input the yaml file and the required service using flag
	var argFile string
	var env string
	svclist := list.New()
	fmt.Print("INFO: 1. Validating if chart file exists....")
	flag.StringVar(&argFile, "f", "", "YAML file to parse.")
	service := flag.String("s", "", "a string")
	flag.StringVar(&env, "e", "", "a string var")
	flag.Parse()

	if argFile == "" {
		fmt.Println("\n\tWARNING: Please provide yaml file by using -f option")
		return
	} else {
		fmt.Print("Success\n")
	}

	// Decode the yaml file and assigning the values to a map
	fmt.Print("INFO: 2. Reading chart file to install DIGIT Services....")
	chartFile, err := ioutil.ReadFile(argFile)
	if err != nil {
		fmt.Println("\n\tERROR: Reading file =>", argFile, err)
		return
	} else {
		fmt.Print("Success\n")
	}

	// Parse the yaml values
	fmt.Print("INFO: 3. Parsing chart file details....")
	fullChart := Digit{}
	err = yaml.Unmarshal(chartFile, &fullChart)
	if err != nil {
		fmt.Println("\n\tERROR: Parsing => ", argFile, err)
		return
	} else {
		fmt.Print("Success\n")
	}

	// Mapping the images to servicename
	fmt.Print("INFO: 4. Reading all services undier the service category....")
	var m = make(map[string][]string)
	set := NewSet()
	for _, s := range fullChart.Modules {
		m[s.Name] = s.Services
	}
	fmt.Print("Success\n")

	//Checking dependencies of service on core or buisness services etc.
	fmt.Println("INFO: 5. Mapping dependancies to the service category....")
	var argStr string = ""

	getService(fullChart, *service, *set, svclist)

	for element := svclist.Front(); element != nil; element = element.Next() {
		for _, service := range m[element.Value.(string)] {
			argStr = argStr + service
			if element.Next() != nil {
				argStr = argStr + ","
			}

		}
	}

	goDeployCmd := fmt.Sprintf("go run deploy-as-code/egov-deployer/main.go deploy -e %s '%s' -p", env, argStr)

	parts := strings.Fields(goDeployCmd)

	fmt.Println("Printing full command part", parts)

	//	The first part is the command, the rest are the args:
	head := parts[0]
	args := parts[1:len(parts)]

	//	Format the command
	cmd := exec.Command(head, args...)
	/*for _, arg := range cmd.Args {
		fmt.Printf("Result: %v\n", arg)
	}*/

	//capture stdout and stderr:
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	//	Run the command
	err = cmd.Run()

	if err != nil {
		fmt.Printf("Error phrase: %q\n", err)
	}

	fmt.Printf("Result: %v / %v", out.String(), stderr.String())

}

func getService(fullChart Digit, service string, set Set, svclist *list.List) {
	for _, s := range fullChart.Modules {
		if s.Name == service {
			if set.Add(service) {
				svclist.PushFront(service) //Add services into the list
				if s.Dependencies != nil {
					for _, deps := range s.Dependencies {
						getService(fullChart, deps, set, svclist)
					}
				}
			}
		}
	}
}
