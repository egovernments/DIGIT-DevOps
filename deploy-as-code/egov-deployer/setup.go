package main

import (
	"bytes"
	"container/list"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"strings"

	"gopkg.in/yaml.v2"
)

//Defining a struct to parse the yaml file
type Chart struct {
	Version string `yaml:"version"`
	Modules []struct {
		Name         string   `yaml:"name"`
		Services     []string `yaml:"services"`
		Dependencies []string `yaml:"dependencies,omitempty"`
	} `yaml:"modules"`
}

type mSet struct {
	set map[string]bool
}

func createSet() *mSet {
	return &mSet{make(map[string]bool)}
}
func (set *mSet) Add(i string) bool {
	_, found := set.set[i]
	set.set[i] = true
	return !found //False if it existed already
}
func (set *mSet) Get(i string) bool {
	_, found := set.set[i]
	return found
}

func main() {
	var modules []string
	svclist := list.New()
	mset := createSet()
	var argStr string = ""
	var jobFolderName = os.Getenv("job")
	var versionFile = os.Getenv("version")
	var envFile = os.Getenv("envFile")
	var deployClusterConfig = os.Getenv("clusterConfig")

	argFile := "../helm/release_charts/" + jobFolderName + "/dependancy_chart-" + jobFolderName + "-" + versionFile + ".yaml"
	//fmt.Println(argFile)
	// Decode the yaml file and assigning the values to a map
	chartFile, err := ioutil.ReadFile(argFile)
	if err != nil {
		fmt.Println("\n\tERROR: Reading file =>", argFile, err)
		return
	}
	//fmt.Println(chartFile)
	// Parse the yaml values
	fullChart := Chart{}
	err = yaml.Unmarshal(chartFile, &fullChart)
	if err != nil {
		fmt.Println("\n\tERROR: Parsing => ", argFile, err)
		return
	}

	// Mapping the images to servicename
	var m = make(map[string][]string)
	for _, s := range fullChart.Modules {
		m[s.Name] = s.Services
		if strings.Contains(s.Name, "m_") {
			modules = append(modules, s.Name)
		}
	}

	if modules != nil {
		for _, mod := range modules {
			getServices(fullChart, mod, *mset, svclist)
		}
		for element := svclist.Front(); element != nil; element = element.Next() {
			imglist := m[element.Value.(string)]
			imglistsize := len(imglist)
			for i, service := range imglist {
				argStr = argStr + service
				if !(element.Next() == nil && i == imglistsize-1) {
					argStr = argStr + ","
				}

			}
		}

		var goDeployCmd string

		goDeployCmd = fmt.Sprintf("./egov-deployer deploy -e %s %s", envFile, argStr)

		if deployClusterConfig == "Yes" {
			goDeployCmd = fmt.Sprintf("./egov-deployer deploy -c -e %s %s", envFile, argStr)
		}

		fmt.Println(goDeployCmd)

		/* err := executeCommand(goDeployCmd)
		if err == nil {
			fmt.Println("We are done with the deployment. You can start using the services. Thank You!!!")
			return
		} */

	}

}

func getServices(fullChart Chart, service string, set mSet, svclist *list.List) {
	for _, s := range fullChart.Modules {
		if s.Name == service {
			if set.Add(service) {
				svclist.PushFront(service) //Add services into the list
				if s.Dependencies != nil {
					for _, deps := range s.Dependencies {
						getServices(fullChart, deps, set, svclist)
					}
				}
			}
		}
	}
}

func executeCommand(command string) error {
	var err error
	parts := strings.Fields(command)
	head := parts[0]
	args := parts[1:len(parts)]
	//	Format the command
	cmd := exec.Command(head, args...)

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = io.MultiWriter(os.Stdout, &stdoutBuf)
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderrBuf)

	err = cmd.Run()
	if err != nil {
		log.Fatalf("cmd.Run() failed with %s\n", err)
	}
	return err
}
