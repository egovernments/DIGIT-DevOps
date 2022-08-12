package main

import (
	"bytes"
	"container/list"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"strings"
	s "strings"

	"github.com/manifoldco/promptui"
	"gopkg.in/yaml.v2"
)

var Reset = "\033[0m"
var Red = "\033[31m"
var Green = "\033[32m"
var Yellow = "\033[33m"
var Blue = "\033[34m"
var Purple = "\033[35m"
var Cyan = "\033[36m"
var Gray = "\033[37m"
var White = "\033[97m"

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
	var versionfiles []string
	var envfiles []string
	var modules []string
	var selectedMod []string
	svclist := list.New()
	set := NewSet()
	var argStr string = ""
	var releaseChartDir string = "../helm/product-release-charts/"

	fmt.Println(string(Green), "\n*******  Welcome to DIGIT INSTALLATION!!! Please ensure the Pre-requsites before you proceed *********\n")
	const sPreReq = "\bPre-requsites (Please Read Carefully):\n\tDIGIT Platform is a combination of multiple microservices that are packaged as docker containers that can be run on any supported infra like dockercompose, kubernetes, etc. Here we'll have a setup baselined for kubernetes.\nHence the following are mandatory to have it before you proceed.\n\t1. Kubernetes(K8s) Cluster.\n\t\t[a] Local: If you do not have k8s, using this link you can create k8s cluster on your local or on a VM.\n\t\t[b] Cloud: If you have your cloud account like AWS, Azure, GCP, SDC or NIC you can follow this link to create k8s.\n\t2. Post the k8s cluster creation you should get the Kubeconfig file, which you have saved in your local machine.\n\t3. Helm installed on your local, follow this link to install\n\t4. Target Env Deployment config file, refer here for the sample template and fill your env specific values.\n\t5. If you want to use encrypted values instead of plain-text for your sensitive configuration, install sops by using this link.\n\nWell! We are good to get started when all the above pre-requistes are met, if not abort it here (Ctl+c) set-it up, come back and rerun the script."
	// Get the Proceedual of the user
	fmt.Println(string(Cyan), sPreReq)
	//var proceedQuestion string
	preReqConfirm := []string{"Yes", "No"}
	var proceed string = ""
	proceed, _ = sel(preReqConfirm, "Are you good to proceed?")
	if proceed == "Yes" {
		contextset := setClusterContext()
		if contextset {
			// Get the versions from the chart and display it to user to select
			file, err := os.Open(releaseChartDir)
			if err != nil {
				log.Fatalf("failed opening directory: %s", err)
			}
			defer file.Close()

			prodList, _ := file.Readdirnames(0) // 0 to read all files and folders

			var product string = ""
			product, _ = sel(prodList, "Which Product would you like to install, Please Select")
			if product != "" {
				files, err := ioutil.ReadDir(releaseChartDir + product)
				if err != nil {
					log.Fatal(err)
				}

				for _, f := range files {
					name := f.Name()
					versionfiles = append(versionfiles, name[s.Index(name, "-")+1:s.Index(name, ".y")])
				}
				var version string = ""
				version, _ = sel(versionfiles, "Which version of the product would like to install, Select below")
				if version != "" {
					argFile := releaseChartDir + product + "/dependency_chart-" + version + ".yaml"
					
					// Decode the yaml file and assigning the values to a map
					chartFile, err := ioutil.ReadFile(argFile)
					if err != nil {
						fmt.Println("\n\tERROR: Reading file =>", argFile, err)
						return
					}

					// Parse the yaml values
					fullChart := Digit{}
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
					modules = append(modules, "Exit")
					result, err := sel(modules, "Select the DIGIT modules that you want to install, choose Exit to complete selection")
					//if err == nil {
					for result != "Exit" && err == nil {
						selectedMod = append(selectedMod, result)
						result, err = sel(modules, "Select the modules you want to install, choose Exit to complete selection")
					}
					if selectedMod != nil {
						for _, mod := range selectedMod {
							getService(fullChart, mod, *set, svclist)
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

						envfilesFromDir, err := ioutil.ReadDir("../helm/environments/")
						if err != nil {
							log.Fatal(err)
						}
						for _, envfile := range envfilesFromDir {
							filename := envfile.Name()
							if !s.Contains(filename, "secrets") {
								envfiles = append(envfiles, filename[0:s.Index(filename, ".yaml")])
							}
						}

						// Choose the env
						var env string = ""
						env, err = sel(envfiles, "Choose the target env files that are identified from your local configs")
						if env != "" {
							confirm := []string{"Yes", "No"}

							var goDeployCmd string = fmt.Sprintf("go run main.go deploy -c -e %s %s", env, argStr)
							var previewDeployCmd string = fmt.Sprintf("%s -p", goDeployCmd)

							preview, _ := sel(confirm, "Do you want to preview the k8s manifests before the actual Deployment")

							if preview == "Yes" {
								fmt.Println("That's cool... The preview is getting loaded. Please review it and decide to proceed with the deployment")
								err := execCommand(previewDeployCmd)
								if err == nil {
									fmt.Println("You can now start actual deployment")
									err := execCommand(goDeployCmd)
									if err == nil {
										fmt.Println("We are done with the deployment. You can start using the services. Thank You!!!")
										return
									} else {
										fmt.Println("Something went wrong, refer the error\n")
										fmt.Println(err)
									}
									return
								} else {
									fmt.Println("Something went wrong, refer the error\n")
									fmt.Println(err)
								}
							} else {
								consent, _ := sel(confirm, "Are we good to proceed with the actual deployment?")
								if consent == "Yes" {
									fmt.Println("Whola!, That's great... Sit back and wait for the deployment to complete in about 10 min")
									err := execCommand(goDeployCmd)
									if err == nil {
										fmt.Println("We are done with the deployment. You can start using the services. Thank You!!!")
										fmt.Println("Hope I made your life easy with the deployment ... Have a goodd day !!!")
										return
									} else {
										fmt.Println("Something went wrong, refer the error\n")
										fmt.Println(err)
									}
								}

							}
						}
					}
				}
			}
		}
	}
	fmt.Println("")
	endScript()
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

func execCommand(command string) error {
	var err error
	parts := strings.Fields(command)
	//log.Println("Printing full command part", parts)
	//	The first part is the command, the rest are the args:
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

func setClusterContext() bool {
	var contextset bool = false
	var kubeconfig string = ""

	validatepath := func(input string) error {
		_, err := os.Stat(input)
		if os.IsNotExist(err) {
			return errors.New("The File does not exist in the given path")
		}
		return nil
	}

	kubeconfig = enterValue(validatepath, "Please enter the fully qualified path of your kubeconfig file")

	if kubeconfig != "" {
		getcontextcmd := fmt.Sprintf("kubectl config get-contexts --kubeconfig=%s", kubeconfig)
		err := execCommand(getcontextcmd)
		if err == nil {
			context := enterValue(nil, "Please enter the cluster context to be used from the avaliable contexts")
			if context != "" {
				usecontextcmd := fmt.Sprintf("kubectl config use-context %s --kubeconfig=%s", context, kubeconfig)
				err := execCommand(usecontextcmd)
				if err == nil {
					contextset = true
				}
			}
		}
	}
	return contextset
}

func sel(items []string, label string) (string, error) {
	var result string
	var err error
	prompt := promptui.Select{
		Label: label,
		Items: items,
		Size:  30,
	}
	_, result, err = prompt.Run()

	//if err != nil {
	//	fmt.Printf("Invalid Selection %v\n", err)
	//}
	return result, err
}

func enterValue(validate promptui.ValidateFunc, label string) string {
	var result string
	prompt := promptui.Prompt{
		Label:    label,
		Validate: validate,
	}
	result, _ = prompt.Run()

	//if err != nil {
	//	fmt.Printf("Invalid Selection %v\n", err)
	//}
	return result
}

func endScript() {
	fmt.Println("Take your time, You can come back at any time ... Thank You!!!")
	return
}
