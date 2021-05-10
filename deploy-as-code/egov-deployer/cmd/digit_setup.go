package main

import (
	"bytes"
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
	fmt.Print("INFO: 1. Validating if chart file exists....")
	flag.StringVar(&argFile, "f", "", "YAML file to parse.")
	service := flag.String("s", "", "a string")
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
	//fmt.Print("Printing map after the mapping", m)

	//Checking dependencies of service on core or buisness services etc.
	fmt.Println("INFO: 5. Mapping dependancies to the service category....")
	var argStr string
	for _, s := range fullChart.Modules {
		if s.Name == *service {
			if s.Dependencies != nil {
				for _, deps := range s.Dependencies {
					for _, service := range m[deps] {
						set.Add(service) //Put array of images into the set
						if len(argStr) == 0 {
							argStr = service + ","
						} else {
							argStr = argStr + service + ","
						}
					}
				}
			}
			for _, service := range s.Services {
				set.Add(service)
				if len(argStr) == 0 {
					argStr = service + ","
				} else {
					argStr = argStr + service + ","
				}
			}
		}
	}
	fmt.Println(argStr)
	//str := fmt.Sprintf("%v", set)

	//fmt.Println(str)
	parts := strings.Fields("go run main.go deploy -e <desiredEnv> -p <desiredProject>")

	fmt.Println("Printing full command part %s", parts)

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
	cmd.Run()

	//fmt.Printf("Result: %v / %v", out.String(), stderr.String())

}
