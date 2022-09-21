package configs

import (
	"fmt"
	"io/ioutil"
	"log"
	"strings"

	yaml "gopkg.in/yaml.v3"
)

var region = "ap-south-1b"

// Quickstart kubeconfig struct
type Config struct {
	APIVersion string `yaml:"apiVersion"`
	Clusters   []struct {
		Cluster struct {
			CertificateAuthorityData string `yaml:"certificate-authority-data"`
			Server                   string `yaml:"server"`
		} `yaml:"cluster"`
		Name string `yaml:"name"`
	} `yaml:"clusters"`
	Contexts []struct {
		Context struct {
			Cluster string `yaml:"cluster"`
			User    string `yaml:"user"`
		} `yaml:"context"`
		Name string `yaml:"name"`
	} `yaml:"contexts"`
	CurrentContext string `yaml:"current-context"`
	Kind           string `yaml:"kind"`
	Preferences    struct {
	} `yaml:"preferences"`
	Users []struct {
		Name string `yaml:"name"`
		User struct {
			ClientCertificateData string `yaml:"client-certificate-data"`
			ClientKeyData         string `yaml:"client-key-data"`
		} `yaml:"user"`
	} `yaml:"users"`
}

// environment secret struct
type Secret struct {
	ClusterConfigs struct {
		Secrets struct {
			Db struct {
				Username       string `yaml:"username"`
				Password       string `yaml:"password"`
				FlywayUsername string `yaml:"flywayUsername"`
				FlywayPassword string `yaml:"flywayPassword"`
			} `yaml:"db"`
			EgovNotificationSms struct {
				Username string `yaml:"username"`
				Password string `yaml:"password"`
			} `yaml:"egov-notification-sms"`
			EgovFilestore struct {
				AwsKey       string `yaml:"aws-key"`
				AwsSecretKey string `yaml:"aws-secret-key"`
			} `yaml:"egov-filestore"`
			EgovLocation struct {
				Gmapskey string `yaml:"gmapskey"`
			} `yaml:"egov-location"`
			EgovPgService struct {
				AxisMerchantID         string `yaml:"axis-merchant-id"`
				AxisMerchantSecretKey  string `yaml:"axis-merchant-secret-key"`
				AxisMerchantUser       string `yaml:"axis-merchant-user"`
				AxisMerchantPwd        string `yaml:"axis-merchant-pwd"`
				AxisMerchantAccessCode string `yaml:"axis-merchant-access-code"`
				PayuMerchantKey        string `yaml:"payu-merchant-key"`
				PayuMerchantSalt       string `yaml:"payu-merchant-salt"`
			} `yaml:"egov-pg-service"`
			Pgadmin struct {
				AdminEmail    string `yaml:"admin-email"`
				AdminPassword string `yaml:"admin-password"`
				ReadEmail     string `yaml:"read-email"`
				ReadPassword  string `yaml:"read-password"`
			} `yaml:"pgadmin"`
			EgovEncService struct {
				MasterPassword      string `yaml:"master-password"`
				MasterSalt          string `yaml:"master-salt"`
				MasterInitialvector string `yaml:"master-initialvector"`
			} `yaml:"egov-enc-service"`
			EgovNotificationMail struct {
				Mailsenderusername string `yaml:"mailsenderusername"`
				Mailsenderpassword string `yaml:"mailsenderpassword"`
			} `yaml:"egov-notification-mail"`
			GitSync struct {
				SSH        string `yaml:"ssh"`
				KnownHosts string `yaml:"known-hosts"`
			} `yaml:"git-sync"`
			Kibana struct {
				Namespace   string `yaml:"namespace"`
				Credentials string `yaml:"credentials"`
			} `yaml:"kibana"`
			EgovSiMicroservice struct {
				SiMicroserviceUser     string `yaml:"si-microservice-user"`
				SiMicroservicePassword string `yaml:"si-microservice-password"`
				MailSenderPassword     string `yaml:"mail-sender-password"`
			} `yaml:"egov-si-microservice"`
			EgovEdcrNotification struct {
				EdcrMailUsername string `yaml:"edcr-mail-username"`
				EdcrMailPassword string `yaml:"edcr-mail-password"`
				EdcrSmsUsername  string `yaml:"edcr-sms-username"`
				EdcrSmsPassword  string `yaml:"edcr-sms-password"`
			} `yaml:"egov-edcr-notification"`
			Chatbot struct {
				ValuefirstUsername string `yaml:"valuefirst-username"`
				ValuefirstPassword string `yaml:"valuefirst-password"`
			} `yaml:"chatbot"`
			EgovUserChatbot struct {
				CitizenLoginPasswordOtpFixedValue string `yaml:"citizen-login-password-otp-fixed-value"`
			} `yaml:"egov-user-chatbot"`
			Oauth2Proxy struct {
				ClientID     string `yaml:"clientID"`
				ClientSecret string `yaml:"clientSecret"`
				CookieSecret string `yaml:"cookieSecret"`
			} `yaml:"oauth2-proxy"`
		} `yaml:"secrets"`
	} `yaml:"cluster-configs"`
}

//terrafrom struct
type Output struct {
	Outputs struct {
		ClusterEndpoint struct {
			Value string `json:"value"`
		} `json:"cluster_endpoint"`
		DbInstanceEndpoint struct {
			Value string `json:"value"`
		} `json:"db_instance_endpoint"`
		DbInstanceName struct {
			Value string `json:"value"`
		} `json:"db_instance_name"`
		DbInstancePort struct {
			Value int `json:"value"`
		} `json:"db_instance_port"`
		DbInstanceUsername struct {
			Value string `json:"value"`
		} `json:"db_instance_username"`
		EsDataVolumeIds struct {
			Value []string `json:"value"`
		} `json:"es_data_volume_ids"`
		EsMasterVolumeIds struct {
			Value []string `json:"value"`
		} `json:"es_master_volume_ids"`
		KafkaVolIds struct {
			Value []string `json:"value"`
		} `json:"kafka_vol_ids"`
		KubectlConfig struct {
			Value string `json:"value"`
		} `json:"kubectl_config"`
		PrivateSubnets struct {
			Value []string `json:"value"`
		} `json:"private_subnets"`
		PublicSubnets struct {
			Value []string `json:"value"`
		} `json:"public_subnets"`
		VpcID struct {
			Value string `json:"value"`
		} `json:"vpc_id"`
		ZookeeperVolumeIds struct {
			Value []string `json:"value"`
		} `json:"zookeeper_volume_ids"`
	} `json:"outputs"`
}
type Quickstart struct {
	Outputs struct {
		PublicIP struct {
			Value string `json:"value"`
		} `json:"public_ip"`
	} `json:"outputs"`
	Resources []struct {
		Instances []struct {
			Attributes struct {
				PrivateIP string `json:"private_ip"`
			} `json:"attributes"`
		} `json:"instances"`
	} `json:"resources"`
}

func DeployConfig(Config map[string]interface{}, kvids []string, zvids []string, esdids []string, esmids []string, modules []string, smsproceed string, fileproceed string, botproceed string, flag string) {

	file, err := ioutil.ReadFile("DIGIT-DevOps/config-as-code/environments/egov-demo.yaml")
	if err != nil {
		log.Printf("%v", err)
	}
	var data map[string]interface{}
	ModData := make(map[string]interface{})
	err = yaml.Unmarshal(file, &data)
	if err != nil {
		log.Printf("%v", err)
	}
	for i := range data {
		if i == "global" {
			Global := data[i].(map[string]interface{})
			for j := range Global {
				if j == "domain" {
					Global[j] = Config["Domain"]
				}
			}
		}
		if i == "cluster-configs" {
			// fmt.Println("found cluster-configs")
			ClusterConfigs := data[i].(map[string]interface{})
			for j := range ClusterConfigs {
				if j == "configmaps" {
					// fmt.Println("found configmaps")
					Configmaps := ClusterConfigs[j].(map[string]interface{})
					for k := range Configmaps {
						if k == "egov-config" {
							// fmt.Println("found egov-config")
							EgovConfig := Configmaps[k].(map[string]interface{})
							for l := range EgovConfig {
								if l == "data" {
									// fmt.Println("found data")
									Data := EgovConfig[l].(map[string]interface{})
									for m := range Data {
										if m == "db-host" {
											Host := Config["db-host"].(string)
											provider := Host[:strings.IndexByte(Host, ':')]
											Data[m] = provider
										}
										if m == "db-name" {
											Data[m] = Config["db_name"]
										}
										if m == "db-url" {
											url := fmt.Sprintf("jdbc:postgresql://%s/%s", Config["db-host"], Config["db_name"])
											Data[m] = url
										}
										if m == "domain" {
											Data[m] = Config["Domain"]
										}
										if m == "egov-services-fqdn-name" {
											fqdn := fmt.Sprintf("https://%s/", Config["Domain"])
											Data[m] = fqdn
										}
										if m == "s3-assets-bucket" {

										}
										if m == "es-host" {

										}
										if m == "es-indexer-host" {

										}
										if m == "flyway-locations" {

										}
										if m == "kafka-brokers" {

										}
										if m == "kafka-infra-brokers" {

										}
										if m == "logging-level-jdbc" {

										}
										if m == "mobile-validation-workaround" {

										}
										if m == "serializers-timezone-in-ist" {

										}
										if m == "server-tomcat-max-connections" {

										}
										if m == "server-tomcat-max-threads" {

										}
										if m == "sms-enabled" {

										}
										if m == "spring-datasource-tomcat-initialSize" {

										}
										if m == "spring-datasource-tomcat-max-active" {

										}
										if m == "spring-jpa-show-sql" {

										}
										if m == "timezone" {

										}
										if m == "tracer-errors-provideexceptionindetails" {

										}
									}
								}
							}
						}

					}
				}
			}
		}
		if i == "egov-mdms-service" || i == "egov-indexer" || i == "egov-persister" || i == "egov-data-uploader" || i == "egov-searcher" || i == "dashboard-analytics" || i == "dashboard-ingest" || i == "report" || i == "pdf-service" {
			// fmt.Println("in mdms")
			Service := data[i].(map[string]interface{})
			for j := range Service {
				if j == "search-yaml-path" {

				}
				if j == "config-schema-paths" {

				}
				if j == "replicas" {

				}
				if j == "mdms-path" {

				}
				if j == "heap" {

				}
				if j == "memory_limits" {

				}
				if j == "mdms-path" {

				}
				if j == "persist-yml-path" {

				}
				if j == "initContainers" {
					// fmt.Println("in init")
					InitContainers := Service[j].(map[string]interface{})
					for k := range InitContainers {
						if k == "gitSync" {
							// fmt.Println("in git sync")
							GitSync := InitContainers[k].(map[string]interface{})
							for l := range GitSync {
								if l == "branch" {
									GitSync[l] = Config["BranchName"]
								}
								if l == "repo" {

								}
							}
						}
					}
				}
				if j == "mdms-folder" {

				}
				if j == "masters-config-url" {

				}
				if j == "java-args" {

				}
				if j == "egov-indexer-yaml-repo-path" {

				}
			}
		}
		if i == "cert-manager" {
			CertManager := data[i].(map[string]interface{})
			for j := range CertManager {
				if j == "email" {
					CertManager[j] = ""
				}
			}
		}
		if i == "kafka-v2" {
			KafkaV2 := data[i].(map[string]interface{})
			for j := range KafkaV2 {
				if j == "persistence" {
					Persistence := KafkaV2[j].(map[string]interface{})
					for k := range Persistence {
						if k == "aws" {
							Aws := Persistence[k].([]interface{})
							N := 0
							for l := range Aws {
								Volume := Aws[l].(map[string]interface{})
								for m := range Volume {
									if m == "volumeId" && N == l {
										Volume[m] = kvids[l]
									}
									if m == "zone" {
										Volume[m] = region
									}
								}
								N++

							}
						}
					}
				}
			}
		}
		if i == "zookeeper-v2" {
			ZookeeperV2 := data[i].(map[string]interface{})
			for j := range ZookeeperV2 {
				if j == "persistence" {
					Persistence := ZookeeperV2[j].(map[string]interface{})
					for k := range Persistence {
						if k == "aws" {
							Aws := Persistence[k].([]interface{})
							N := 0
							for l := range Aws {
								Volume := Aws[l].(map[string]interface{})
								for m := range Volume {
									if m == "volumeId" && N == l {
										Volume[m] = zvids[l]
									}
									if m == "zone" {
										Volume[m] = region
									}
								}
								N++

							}
						}
					}
				}
			}
		}
		if i == "elasticsearch-data-v1" {
			ElasticsearchDataV1 := data[i].(map[string]interface{})
			for j := range ElasticsearchDataV1 {
				if j == "persistence" {
					Persistence := ElasticsearchDataV1[j].(map[string]interface{})
					for k := range Persistence {
						if k == "aws" {
							Aws := Persistence[k].([]interface{})
							N := 0
							for l := range Aws {
								NesteM := Aws[l].(map[string]interface{})
								for m := range NesteM {
									if m == "volumeId" && N == l {
										NesteM[m] = esdids[l]
									}
									if m == "zone" {
										NesteM[m] = region
									}
								}
								N++

							}
						}
					}
				}
			}
		}
		if i == "elasticsearch-master-v1" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "persistence" {
					nest := NestedMap[j].(map[string]interface{})
					for k := range nest {
						if k == "aws" {
							Neste := nest[k].([]interface{})
							N := 0
							for l := range Neste {
								NesteM := Neste[l].(map[string]interface{})
								for m := range NesteM {
									if m == "volumeId" && N == l {
										NesteM[m] = esmids[l]
									}
									if m == "zone" {
										NesteM[m] = region
									}
								}
								N++

							}
						}
					}
				}
			}
		}
		if i == "employee" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "dashboard-url" {

				}
				if j == "custom-js-injection" {

				}
			}
		}
		if i == "citizen" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "custom-js-injection" {

				}
			}
		}
		if i == "digit-ui" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "custom-js-injection" {
				}
			}
		}
		if i == "egov-filestore" && fileproceed == "yes" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "volume" {

				}
				if j == "is-bucket-fixed" {

				}
				if j == "minio.url" {

				}
				if j == "aws.s3.url" {

				}
				if j == "is-s3-enabled" {

				}
				if j == "minio-enabled" {

				}
				if j == "allowed-file-formats-map" {

				}
				if j == "llowed-file-formats" {

				}
				if j == "filestore-url-validity" {

				}
				if j == "fixed-bucketname" {
					NestedMap[j] = Config["fixed-bucket"]
				}
			}

		}
		if i == "egov-notification-sms" && smsproceed == "yes" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "sms-provider-url" {
					NestedMap[j] = Config["sms-provider-url"]
				}
				if j == "sms.provider.class" {

				}
				if j == "sms.provider.contentType" {

				}
				if j == "sms-config-map" {

				}
				if j == "sms-gateway-to-use" {
					NestedMap[j] = Config["sms-gateway-to-use"]
				}
				if j == "sms-sender" {
					NestedMap[j] = Config["sms-sender"]
				}
				if j == "sms-sender-requesttype" {

				}
				if j == "sms-custom-config" {

				}
				if j == "sms-extra-req-params" {

				}
				if j == "sms-sender-req-param-name" {

				}
				if j == "sms-sender-username-req-param-name" {

				}
				if j == "sms-sender-password-req-param-name" {

				}
				if j == "sms-destination-mobile-req-param-name" {

				}
				if j == "sms-message-req-param-name" {

				}
				if j == "sms-error-codes" {

				}
			}
			ModData["egov-notification-sms"] = data["egov-notification-sms"]
		}
		if i == "egov-user" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "heap" {

				}
				if j == "memory_limits" {

				}
				if j == "otp-validation" {

				}
				if j == "citizen-otp-enabled" {

				}
				if j == "employee-otp-enabled" {

				}
				if j == "access-token-validity" {

				}
				if j == "refresh-token-validity" {

				}
				if j == "default-password-expiry" {

				}
				if j == "mobile-number-validation" {

				}
				if j == "roles-state-level" {

				}
				if j == "zen-registration-withlogin" {

				}
				if j == "citizen-otp-fixed" {

				}
				if j == "citizen-otp-fixed-enabled" {

				}
				if j == "egov-state-level-tenant-id" {

				}
				if j == "decryption-abac-enabled" {

				}
			}
		}
		if i == "chatbot" && botproceed == "yes" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "kafka-topics-partition-count" {

				}
				if j == "kafka-topics-replication-factor" {

				}
				if j == "kafka-consumer-poll-ms" {

				}
				if j == "kafka-producer-linger-ms" {

				}
				if j == "contact-card-whatsapp-number" {

				}
				if j == "contact-card-whatsapp-name" {

				}
				if j == "valuefirst-whatsapp-number" {

				}
				if j == "valuefirst-notification-assigned-templateid" {

				}
				if j == "valuefirst-notification-resolved-templateid" {

				}
				if j == "valuefirst-notification-rejected-templateid" {

				}
				if j == "valuefirst-notification-reassigned-templateid" {

				}
				if j == "valuefirst-notification-commented-templateid" {

				}
				if j == "valuefirst-notification-welcome-templateid" {

				}
				if j == "valuefirst-notification-root-templateid" {

				}
				if j == "valuefirst-send-message-url" {

				}
				if j == "user-service-chatbot-citizen-passwrord" {

				}
			}
			ModData["chatbot"] = data["chatbot"]
		}
		if i == "bpa-services" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "memory_limits" {

				}
				if j == "java-args" {

				}
				if j == "java-debug" {

				}
				if j == "tracing-enabled" {

				}
				if j == "egov.idgen.bpa.applicationNum.format" {

				}
			}
		}
		if i == "bpa-calculator" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "memory_limits" {

				}
				if j == "java-args" {

				}
				if j == "java-debug" {

				}
				if j == "tracing-enabled" {

				}
			}
		}
		if i == "ws-services" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "wcid-format" {

				}
			}
		}
		if i == "sw-services" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "scid-format" {

				}
			}
		}
		if i == "egov-pg-service" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "axis" {

				}
			}
		}
		if i == "report" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "heap" {

				}
				if j == "tracing-enabled" {

				}
				if j == "spring-datasource-tomcat-max-active" {

				}
				if j == "initContainers" {
					NestedM := NestedMap[j].(map[string]interface{})
					for k := range NestedM {
						if k == "gitSync" {
							Neste := NestedM[k].(map[string]interface{})
							for l := range Neste {
								if l == "repo" {

								}
								if l == "branch" {
									Neste[l] = Config["BranchName"]
								}
							}
						}
					}
				}
				if j == "report-locationsfile-path" {

				}
			}
		}
		if i == "pdf-service" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "initContainers" {
					NestedM := NestedMap[j].(map[string]interface{})
					for k := range NestedM {
						if k == "gitSync" {
							Neste := NestedM[k].(map[string]interface{})
							for l := range Neste {
								if l == "repo" {

								}
								if l == "branch" {
									Neste[l] = Config["BranchName"]
								}
							}
						}
					}
				}
				if j == "data-config-urls" {

				}
				if j == "format-config-urls" {

				}

			}
		}
		if i == "egf-master" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "db-url" {

				}
				if j == "memory_limits" {

				}
				if j == "heap" {

				}

			}
		}
		if i == "egov-custom-consumer" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "erp-host" {

				}
			}
		}
		if i == "egov-apportion-service" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "memory_limits" {

				}
				if j == "heap" {

				}
			}
		}
		if i == "redoc" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "replicas" {

				}
				if j == "images" {

				}
				if j == "service_type" {

				}
			}
		}
		if i == "redoc" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "images" {

				}
				if j == "replicas" {

				}
				if j == "default-backend-service" {

				}
				if j == "namespace" {

				}
				if j == "cert-issuer" {

				}
				if j == "ssl-protocols" {

				}
				if j == "ssl-ciphers" {

				}
				if j == "ssl-ecdh-curve" {

				}
			}
		}
		if i == "cert-manager" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "email" {

				}
			}
		}
		if i == "zuul" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "replicas" {

				}
				if j == "custom-filter-property" {

				}
				if j == "tracing-enabled" {

				}
				if j == "heap" {

				}
				if j == "server-tomcat-max-threads" {

				}
				if j == "server-tomcat-max-connections" {

				}
				if j == "egov-open-endpoints-whitelist" {

				}
				if j == "egov-mixed-mode-endpoints-whitelist" {

				}
			}
		}
		if i == "collection-services" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "receiptnumber-servicebased" {

				}
				if j == "receipt-search-paginate" {

				}
				if j == "receipt-search-defaultsize" {

				}
				if j == "user-create-enabled" {

				}
			}
		}
		if i == "collection-receipt-voucher-consumer" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "jalandhar-erp-host" {

				}
				if j == "mohali-erp-host" {

				}
				if j == "nayagaon-erp-host" {

				}
				if j == "amritsar-erp-host" {

				}
				if j == "kharar-erp-host" {

				}
				if j == "zirakpur-erp-host" {

				}
			}
		}
		if i == "finance-collections-voucher-consumer" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "erp-env-name" {

				}
				if j == "erp-domain-name" {

				}
			}
		}
		if i == "rainmaker-pgr" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "notification-sms-enabled" {

				}
				if j == "notification-email-enabled" {

				}
				if j == "new-complaint-enabled" {

				}
				if j == "reassign-complaint-enabled" {

				}
				if j == "reopen-complaint-enabled" {

				}
				if j == "comment-by-employee-notif-enabled" {

				}
				if j == "notification-allowed-status" {

				}
			}
		}
		if i == "pt-services-v2" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "pt-userevents-pay-link" {

				}
			}
		}
		if i == "pt-calculator-v2" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "logging-level" {

				}
			}
		}
		if i == "tl-services" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "heap" {

				}
				if j == "memory_limits" {

				}
				if j == "java-args" {

				}
				if j == "tl-application-num-format" {

				}
				if j == "tl-license-num-format" {

				}
				if j == "tl-userevents-pay-link" {

				}
				if j == "tl-payment-topic-name" {

				}
				if j == "host-link" {

				}
				if j == "pdf-link" {

				}
				if j == "tl-search-default-limit" {

				}
			}
		}
		if i == "egov-hrms" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "java-args" {

				}
				if j == "heap" {

				}
				if j == "employee-applink" {

				}
			}
		}
		if i == "egov-weekly-impact-notifier" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "mail-to-address" {

				}
				if j == "mail-interval-in-secs" {

				}
				if j == "schedule" {

				}
			}
		}
		if i == "kafka-config" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "topics" {

				}
				if j == "zookeeper-connect" {

				}
				if j == "kafka-brokers" {

				}
			}
		}
		if i == "logging-config" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "es-host" {

				}
				if j == "es-port" {

				}
			}
		}
		if i == "jaeger-config" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "host" {

				}
				if j == "port" {

				}
				if j == "sampler-type" {

				}
				if j == "sampler-param" {

				}
				if j == "sampling-strategies" {

				}
			}
		}
		if i == "redis" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "replicas" {

				}
				if j == "images" {

				}
			}
		}
		if i == "playground" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "replicas" {

				}
				if j == "images" {

				}
			}
		}
		if i == "fluent-bit" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "images" {

				}
				if j == "egov-services-log-topic" {

				}
				if j == "egov-infra-log-topic" {

				}
			}
		}
		if i == "egov-workflow-v2" {
			NestedMap := data[i].(map[string]interface{})
			for j := range NestedMap {
				if j == "logging-level" {

				}
				if j == "java-args" {

				}
				if j == "heap" {

				}
				if j == "workflow-statelevel" {

				}
				if j == "host-link" {

				}
				if j == "pdf-link" {

				}
			}
		}
	}
	ModData["global"] = data["global"]
	ModData["cluster-configs"] = data["cluster-configs"]
	ModData["employee"] = data["employee"]
	ModData["citizen"] = data["citizen"]
	ModData["digit-ui"] = data["digit-ui"]
	ModData["egov-filestore"] = data["egov-filestore"]
	ModData["egov-idgen"] = data["egov-idgen"]
	ModData["egov-user"] = data["egov-user"]
	ModData["egov-indexer"] = data["egov-indexer"]
	ModData["egov-persister"] = data["egov-persister"]
	ModData["egov-data-uploader"] = data["egov-data-uploader"]
	ModData["egov-searcher"] = data["egov-searcher"]
	ModData["report"] = data["report"]
	ModData["pdf-service"] = data["pdf-service"]
	ModData["egf-master"] = data["egf-master"]
	ModData["egov-custom-consumer"] = data["egov-custom-consumer"]
	ModData["egov-apportion-service"] = data["egov-apportion-service"]
	ModData["redoc"] = data["redoc"]
	ModData["nginx-ingress"] = data["nginx-ingress"]
	ModData["cert-manager"] = data["cert-manager"]
	ModData["zuul"] = data["zuul"]
	ModData["collection-services"] = data["collection-services"]
	ModData["collection-receipt-voucher-consumer"] = data["collection-receipt-voucher-consumer"]
	ModData["finance-collections-voucher-consumer"] = data["finance-collections-voucher-consumer"]
	ModData["egov-workflow-v2"] = data["egov-workflow-v2"]
	ModData["egov-hrms"] = data["egov-hrms"]
	ModData["egov-weekly-impact-notifier"] = data["egov-weekly-impact-notifier"]
	ModData["kafka-config"] = data["kafka-config"]
	ModData["logging-config"] = data["logging-config"]
	ModData["jaeger-config"] = data["jaeger-config"]
	ModData["redis"] = data["redis"]
	ModData["playground"] = data["playground"]
	ModData["fluent-bit"] = data["fluent-bit"]
	ModData["kafka-v2"] = data["kafka-v2"]
	ModData["zookeeper-v2"] = data["zookeeper-v2"]
	ModData["elasticsearch-data-v1"] = data["elasticsearch-data-v1"]
	ModData["elasticsearch-master-v1"] = data["elasticsearch-master-v1"]
	ModData["es-curator"] = data["es-curator"]
	for i := range modules {
		if modules[i] == "m_pgr" {
			ModData["egov-pg-service"] = data["egov-pg-service"]
			ModData["rainmaker-pgr"] = data["rainmaker-pgr"]
		}
		if modules[i] == "m_property-tax" {
			ModData["pt-services-v2"] = data["pt-services-v2"]
			ModData["pt-calculator-v2"] = data["pt-calculator-v2"]
		}
		if modules[i] == "m_sewerage" {
			ModData["sw-services"] = data["sw-services"]
		}
		if modules[i] == "m_bpa" {
			ModData["bpa-services"] = data["bpa-services"]
			ModData["bpa-calculator"] = data["bpa-calculator"]
		}
		if modules[i] == "m_trade-license" {
			ModData["tl-services"] = data["tl-services"]
		}
		if modules[i] == "m_firenoc" {

		}
		if modules[i] == "m_water-service" {
			ModData["ws-services"] = data["ws-services"]
		}
		if modules[i] == "m_dss" {
			ModData["dashboard-analytics"] = data["dashboard-analytics"]
			ModData["dashboard-ingest"] = data["dashboard-ingest"]
		}
		if modules[i] == "m_fsm" {

		}
		if modules[i] == "m_echallan" {

		}
		if modules[i] == "m_edcr" {

		}
		if modules[i] == "m_finance" {

		}
	}
	newfile, err := yaml.Marshal(&ModData)
	if err != nil {
		log.Printf("%v", err)

	}
	filename := fmt.Sprintf("../../config-as-code/environments/%s.yaml", Config["file_name"])
	err = ioutil.WriteFile(filename, newfile, 0644)
	if err != nil {
		log.Printf("%v", err)
	}
}

//secrets config

func SecretFile(cluster_name string) {
	var sec Secret
	secret, err := ioutil.ReadFile("DIGIT-DevOps/config-as-code/environments/egov-demo-secrets.yaml")
	if err != nil {
		log.Printf("%v", err)
	}
	err = yaml.Unmarshal(secret, &sec)
	if err != nil {
		log.Printf("%v", err)
	}
	eUsername := sec.ClusterConfigs.Secrets.Db.Username
	fmt.Println(eUsername)
	var Db_Username string
	var Db_Password string
	var Db_FlywayUsername string
	var Db_FlywayPassword string
	var EgovNotificationSms_Username string
	var EgovNotificationSms_Password string
	var EgovFilestore_AwsKey string
	var EgovFilestore_AwsSecretKey string
	var EgovLocation_Gmapskey string
	var EgovPgService_AxisMerchantID string
	var EgovPgService_AxisMerchantSecretKey string
	var EgovPgService_AxisMerchantUser string
	var EgovPgService_AxisMerchantPwd string
	var EgovPgService_AxisMerchantAccessCode string
	var EgovPgService_PayuMerchantKey string
	var EgovPgService_PayuMerchantSalt string
	var Pgadmin_AdminEmail string
	var Pgadmin_AdminPassword string
	var Pgadmin_ReadEmail string
	var Pgadmin_ReadPassword string
	var EgovEncService_MasterPassword string
	var EgovEncService_MasterSalt string
	var EgovEncService_MasterInitialvector string
	var EgovNotificationMail_Mailsenderusername string
	var EgovNotificationMail_Mailsenderpassword string
	var GitSync_SSH string
	var GitSync_KnownHosts string
	var Kibana_Namespace string
	var Kibana_Credentials string
	var EgovSiMicroservice_SiMicroserviceUser string
	var EgovSiMicroservice_SiMicroservicePassword string
	var EgovSiMicroservice_MailSenderPassword string
	var EgovEdcrNotification_EdcrMailUsername string
	var EgovEdcrNotification_EdcrMailPassword string
	var EgovEdcrNotification_EdcrSmsUsername string
	var EgovEdcrNotification_EdcrSmsPassword string
	var Chatbot_ValuefirstUsername string
	var Chatbot_ValuefirstPassword string
	var EgovUserChatbot_CitizenLoginPasswordOtpFixedValue string
	var Oauth2Proxy_ClientID string
	var Oauth2Proxy_ClientSecret string
	var Oauth2Proxy_CookieSecret string

	Username := sec.ClusterConfigs.Secrets.Db.Username
	Password := sec.ClusterConfigs.Secrets.Db.Password
	FlywayUsername := sec.ClusterConfigs.Secrets.Db.FlywayUsername
	FlywayPassword := sec.ClusterConfigs.Secrets.Db.FlywayPassword
	NotUsername := sec.ClusterConfigs.Secrets.EgovNotificationSms.Username
	NotPassword := sec.ClusterConfigs.Secrets.EgovNotificationSms.Password
	AwsKey := sec.ClusterConfigs.Secrets.EgovFilestore.AwsKey
	AwsSecretKey := sec.ClusterConfigs.Secrets.EgovFilestore.AwsSecretKey
	Gmapskey := sec.ClusterConfigs.Secrets.EgovLocation.Gmapskey
	AxisMerchantID := sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantID
	AxisMerchantSecretKey := sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantSecretKey
	AxisMerchantUser := sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantUser
	AxisMerchantPwd := sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantPwd
	AxisMerchantAccessCode := sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantAccessCode
	PayuMerchantKey := sec.ClusterConfigs.Secrets.EgovPgService.PayuMerchantKey
	PayuMerchantSalt := sec.ClusterConfigs.Secrets.EgovPgService.PayuMerchantSalt
	AdminEmail := sec.ClusterConfigs.Secrets.Pgadmin.AdminEmail
	AdminPassword := sec.ClusterConfigs.Secrets.Pgadmin.AdminPassword
	ReadEmail := sec.ClusterConfigs.Secrets.Pgadmin.ReadEmail
	ReadPassword := sec.ClusterConfigs.Secrets.Pgadmin.ReadPassword
	MasterPassword := sec.ClusterConfigs.Secrets.EgovEncService.MasterPassword
	MasterSalt := sec.ClusterConfigs.Secrets.EgovEncService.MasterSalt
	MasterInitialvector := sec.ClusterConfigs.Secrets.EgovEncService.MasterInitialvector
	Mailsenderusername := sec.ClusterConfigs.Secrets.EgovNotificationMail.Mailsenderusername
	Mailsenderpassword := sec.ClusterConfigs.Secrets.EgovNotificationMail.Mailsenderpassword
	SSH := sec.ClusterConfigs.Secrets.GitSync.SSH
	KnownHosts := sec.ClusterConfigs.Secrets.GitSync.KnownHosts
	Namespace := sec.ClusterConfigs.Secrets.Kibana.Namespace
	Credentials := sec.ClusterConfigs.Secrets.Kibana.Credentials
	SiMicroserviceUser := sec.ClusterConfigs.Secrets.EgovSiMicroservice.SiMicroserviceUser
	SiMicroservicePassword := sec.ClusterConfigs.Secrets.EgovSiMicroservice.SiMicroservicePassword
	MailSenderPassword := sec.ClusterConfigs.Secrets.EgovSiMicroservice.MailSenderPassword
	EdcrMailUsername := sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrMailUsername
	EdcrMailPassword := sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrMailPassword
	EdcrSmsUsername := sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrSmsUsername
	EdcrSmsPassword := sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrSmsPassword
	ValuefirstUsername := sec.ClusterConfigs.Secrets.Chatbot.ValuefirstUsername
	ValuefirstPassword := sec.ClusterConfigs.Secrets.Chatbot.ValuefirstPassword
	CitizenLoginPasswordOtpFixedValue := sec.ClusterConfigs.Secrets.EgovUserChatbot.CitizenLoginPasswordOtpFixedValue
	ClientID := sec.ClusterConfigs.Secrets.Oauth2Proxy.ClientID
	ClientSecret := sec.ClusterConfigs.Secrets.Oauth2Proxy.ClientSecret
	CookieSecret := sec.ClusterConfigs.Secrets.Oauth2Proxy.CookieSecret

	fmt.Println(KnownHosts)
	fmt.Println("Enter Db_Username:")
	fmt.Scanln(&Db_Username)
	if Db_Username != "" {
		sec.ClusterConfigs.Secrets.Db.Username = Db_Username
	} else {
		sec.ClusterConfigs.Secrets.Db.Username = Username
	}
	fmt.Println("Enter Db_Password:")
	fmt.Scanln(&Db_Password)
	if Db_Password != "" {
		sec.ClusterConfigs.Secrets.Db.Password = Db_Password
	} else {
		sec.ClusterConfigs.Secrets.Db.Password = Password
	}
	fmt.Println("Enter Db_FlywayUsername:")
	fmt.Scanln(&Db_FlywayUsername)
	if Db_FlywayUsername != "" {
		sec.ClusterConfigs.Secrets.Db.FlywayUsername = Db_FlywayUsername
	} else {
		sec.ClusterConfigs.Secrets.Db.FlywayUsername = FlywayUsername
	}
	fmt.Println("Enter Db_FlywayPassword:")
	fmt.Scanln(&Db_FlywayPassword)
	if Db_FlywayPassword != "" {
		sec.ClusterConfigs.Secrets.Db.FlywayPassword = Db_FlywayPassword
	} else {
		sec.ClusterConfigs.Secrets.Db.FlywayPassword = FlywayPassword
	}
	fmt.Println("Enter EgovNotificationSms_Username:")
	fmt.Scanln(&EgovNotificationSms_Username)
	if EgovNotificationSms_Username != "" {
		sec.ClusterConfigs.Secrets.EgovNotificationSms.Username = EgovNotificationSms_Username
	} else {
		sec.ClusterConfigs.Secrets.EgovNotificationSms.Username = NotUsername
	}
	fmt.Println("Enter EgovNotificationSms_Password:")
	fmt.Scanln(&EgovNotificationSms_Password)
	if EgovNotificationSms_Password != "" {
		sec.ClusterConfigs.Secrets.EgovNotificationSms.Password = EgovNotificationSms_Password
	} else {
		sec.ClusterConfigs.Secrets.EgovNotificationSms.Password = NotPassword
	}
	fmt.Println("Enter EgovFilestore_AwsKey:")
	fmt.Scanln(&EgovFilestore_AwsKey)
	if EgovFilestore_AwsKey != "" {
		sec.ClusterConfigs.Secrets.EgovFilestore.AwsKey = EgovFilestore_AwsKey
	} else {
		sec.ClusterConfigs.Secrets.EgovFilestore.AwsKey = AwsKey
	}
	fmt.Println("Enter EgovFilestore_AwsSecretKey:")
	fmt.Scanln(&EgovFilestore_AwsSecretKey)
	if EgovFilestore_AwsSecretKey != "" {
		sec.ClusterConfigs.Secrets.EgovFilestore.AwsSecretKey = EgovFilestore_AwsSecretKey
	} else {
		sec.ClusterConfigs.Secrets.EgovFilestore.AwsSecretKey = AwsSecretKey
	}
	fmt.Println("Enter EgovLocation_Gmapskey:")
	fmt.Scanln(&EgovLocation_Gmapskey)
	if EgovLocation_Gmapskey != "" {
		sec.ClusterConfigs.Secrets.EgovLocation.Gmapskey = EgovLocation_Gmapskey
	} else {
		sec.ClusterConfigs.Secrets.EgovLocation.Gmapskey = Gmapskey
	}
	fmt.Println("Enter EgovPgService_AxisMerchantID:")
	fmt.Scanln(&EgovPgService_AxisMerchantID)
	if EgovPgService_AxisMerchantID != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantID = EgovPgService_AxisMerchantID
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantID = AxisMerchantID
	}
	fmt.Println("Enter EgovPgService_AxisMerchantSecretKey:")
	fmt.Scanln(&EgovPgService_AxisMerchantSecretKey)
	if EgovPgService_AxisMerchantSecretKey != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantSecretKey = EgovPgService_AxisMerchantSecretKey
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantSecretKey = AxisMerchantSecretKey
	}
	fmt.Println("Enter EgovPgService_AxisMerchantUser:")
	fmt.Scanln(&EgovPgService_AxisMerchantUser)
	if EgovPgService_AxisMerchantUser != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantUser = EgovPgService_AxisMerchantUser
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantUser = AxisMerchantUser
	}
	fmt.Println("Enter EgovPgService_AxisMerchantPwd:")
	fmt.Scanln(&EgovPgService_AxisMerchantPwd)
	if EgovPgService_AxisMerchantPwd != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantPwd = EgovPgService_AxisMerchantPwd
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantPwd = AxisMerchantPwd
	}
	fmt.Println("Enter EgovPgService_AxisMerchantAccessCode:")
	fmt.Scanln(&EgovPgService_AxisMerchantAccessCode)
	if EgovPgService_AxisMerchantAccessCode != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantAccessCode = EgovPgService_AxisMerchantAccessCode
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.AxisMerchantAccessCode = AxisMerchantAccessCode
	}
	fmt.Println("Enter EgovPgService_PayuMerchantKey:")
	fmt.Scanln(&EgovPgService_PayuMerchantKey)
	if EgovPgService_PayuMerchantKey != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.PayuMerchantKey = EgovPgService_PayuMerchantKey
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.PayuMerchantKey = PayuMerchantKey
	}
	fmt.Println("Enter EgovPgService_PayuMerchantSalt:")
	fmt.Scanln(&EgovPgService_PayuMerchantSalt)
	if EgovPgService_PayuMerchantSalt != "" {
		sec.ClusterConfigs.Secrets.EgovPgService.PayuMerchantSalt = EgovPgService_PayuMerchantSalt
	} else {
		sec.ClusterConfigs.Secrets.EgovPgService.PayuMerchantSalt = PayuMerchantSalt
	}
	fmt.Println("Enter Pgadmin_AdminEmail:")
	fmt.Scanln(&Pgadmin_AdminEmail)
	if Pgadmin_AdminEmail != "" {
		sec.ClusterConfigs.Secrets.Pgadmin.AdminEmail = Pgadmin_AdminEmail
	} else {
		sec.ClusterConfigs.Secrets.Pgadmin.AdminEmail = AdminEmail
	}
	fmt.Println("Enter Pgadmin_AdminPassword:")
	fmt.Scanln(&Pgadmin_AdminPassword)
	if Pgadmin_AdminPassword != "" {
		sec.ClusterConfigs.Secrets.Pgadmin.AdminPassword = Pgadmin_AdminPassword
	} else {
		sec.ClusterConfigs.Secrets.Pgadmin.AdminPassword = AdminPassword
	}
	fmt.Println("Enter Pgadmin_ReadEmail:")
	fmt.Scanln(&Pgadmin_ReadEmail)
	if Pgadmin_ReadEmail != "" {
		sec.ClusterConfigs.Secrets.Pgadmin.ReadEmail = Pgadmin_ReadEmail
	} else {
		sec.ClusterConfigs.Secrets.Pgadmin.ReadEmail = ReadEmail
	}
	fmt.Println("Enter Pgadmin_ReadPassword:")
	fmt.Scanln(&Pgadmin_ReadPassword)
	if Pgadmin_ReadPassword != "" {
		sec.ClusterConfigs.Secrets.Pgadmin.ReadPassword = Pgadmin_ReadPassword
	} else {
		sec.ClusterConfigs.Secrets.Pgadmin.ReadPassword = ReadPassword
	}
	fmt.Println("Enter EgovEncService_MasterPassword:")
	fmt.Scanln(&EgovEncService_MasterPassword)
	if EgovEncService_MasterPassword != "" {
		sec.ClusterConfigs.Secrets.EgovEncService.MasterPassword = EgovEncService_MasterPassword
	} else {
		sec.ClusterConfigs.Secrets.EgovEncService.MasterPassword = MasterPassword
	}
	fmt.Println("Enter EgovEncService_MasterSalt:")
	fmt.Scanln(&EgovEncService_MasterSalt)
	if EgovEncService_MasterSalt != "" {
		sec.ClusterConfigs.Secrets.EgovEncService.MasterSalt = EgovEncService_MasterSalt
	} else {
		sec.ClusterConfigs.Secrets.EgovEncService.MasterSalt = MasterSalt
	}
	fmt.Println("Enter EgovEncService_MasterInitialvector:")
	fmt.Scanln(&EgovEncService_MasterInitialvector)
	if EgovEncService_MasterInitialvector != "" {
		sec.ClusterConfigs.Secrets.EgovEncService.MasterInitialvector = EgovEncService_MasterInitialvector
	} else {
		sec.ClusterConfigs.Secrets.EgovEncService.MasterInitialvector = MasterInitialvector
	}
	fmt.Println("Enter EgovNotificationMail_Mailsenderusername:")
	fmt.Scanln(&EgovNotificationMail_Mailsenderusername)
	if EgovNotificationMail_Mailsenderusername != "" {
		sec.ClusterConfigs.Secrets.EgovNotificationMail.Mailsenderusername = EgovNotificationMail_Mailsenderusername
	} else {
		sec.ClusterConfigs.Secrets.EgovNotificationMail.Mailsenderusername = Mailsenderusername
	}
	fmt.Println("Enter EgovNotificationMail_Mailsenderpassword:")
	fmt.Scanln(&EgovNotificationMail_Mailsenderpassword)
	if EgovNotificationMail_Mailsenderpassword != "" {
		sec.ClusterConfigs.Secrets.EgovNotificationMail.Mailsenderpassword = EgovNotificationMail_Mailsenderpassword
	} else {
		sec.ClusterConfigs.Secrets.EgovNotificationMail.Mailsenderpassword = Mailsenderpassword
	}
	fmt.Println("Enter GitSync_SSH:")
	fmt.Scanln(&GitSync_SSH)
	if GitSync_SSH != "" {
		sec.ClusterConfigs.Secrets.GitSync.SSH = GitSync_SSH
	} else {
		sec.ClusterConfigs.Secrets.GitSync.SSH = SSH
	}
	fmt.Println("Enter GitSync_KnownHosts:")
	fmt.Scanln(&GitSync_KnownHosts)
	if GitSync_KnownHosts != "" {
		sec.ClusterConfigs.Secrets.GitSync.KnownHosts = GitSync_KnownHosts
	} else {
		sec.ClusterConfigs.Secrets.GitSync.KnownHosts = KnownHosts
	}
	fmt.Println("Enter Kibana_Namespace:")
	fmt.Scanln(&Kibana_Namespace)
	if Kibana_Namespace != "" {
		sec.ClusterConfigs.Secrets.Kibana.Namespace = Kibana_Namespace
	} else {
		sec.ClusterConfigs.Secrets.Kibana.Namespace = Namespace
	}
	fmt.Println("Enter Kibana_Credentials:")
	fmt.Scanln(&Kibana_Credentials)
	if Kibana_Credentials != "" {
		sec.ClusterConfigs.Secrets.Kibana.Credentials = Kibana_Credentials
	} else {
		sec.ClusterConfigs.Secrets.Kibana.Credentials = Credentials
	}
	fmt.Println("Enter EgovSiMicroservice_SiMicroserviceUser:")
	fmt.Scanln(&EgovSiMicroservice_SiMicroserviceUser)
	if EgovSiMicroservice_SiMicroserviceUser != "" {
		sec.ClusterConfigs.Secrets.EgovSiMicroservice.SiMicroserviceUser = EgovSiMicroservice_SiMicroserviceUser
	} else {
		sec.ClusterConfigs.Secrets.EgovSiMicroservice.SiMicroserviceUser = SiMicroserviceUser
	}
	fmt.Println("Enter EgovSiMicroservice_SiMicroservicePassword:")
	fmt.Scanln(&EgovSiMicroservice_SiMicroservicePassword)
	if EgovSiMicroservice_SiMicroservicePassword != "" {
		sec.ClusterConfigs.Secrets.EgovSiMicroservice.SiMicroservicePassword = EgovSiMicroservice_SiMicroservicePassword
	} else {
		sec.ClusterConfigs.Secrets.EgovSiMicroservice.SiMicroservicePassword = SiMicroservicePassword
	}
	fmt.Println("Enter EgovSiMicroservice_MailSenderPassword:")
	fmt.Scanln(&EgovSiMicroservice_MailSenderPassword)
	if EgovSiMicroservice_MailSenderPassword != "" {
		sec.ClusterConfigs.Secrets.EgovSiMicroservice.MailSenderPassword = EgovSiMicroservice_MailSenderPassword
	} else {
		sec.ClusterConfigs.Secrets.EgovSiMicroservice.MailSenderPassword = MailSenderPassword
	}
	fmt.Println("Enter EgovEdcrNotification_EdcrMailUsername:")
	fmt.Scanln(&EgovEdcrNotification_EdcrMailUsername)
	if EgovEdcrNotification_EdcrMailUsername != "" {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrMailUsername = EgovEdcrNotification_EdcrMailUsername
	} else {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrMailUsername = EdcrMailUsername
	}
	fmt.Println("Enter EgovEdcrNotification_EdcrMailPassword:")
	fmt.Scanln(&EgovEdcrNotification_EdcrMailPassword)
	if EgovEdcrNotification_EdcrMailPassword != "" {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrMailPassword = EgovEdcrNotification_EdcrMailPassword
	} else {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrMailPassword = EdcrMailPassword
	}
	fmt.Println("Enter EgovEdcrNotification_EdcrSmsUsername:")
	fmt.Scanln(&EgovEdcrNotification_EdcrSmsUsername)
	if EgovEdcrNotification_EdcrSmsUsername != "" {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrSmsUsername = EgovEdcrNotification_EdcrSmsUsername
	} else {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrSmsUsername = EdcrSmsUsername
	}
	fmt.Println("Enter EgovEdcrNotification_EdcrSmsPassword:")
	fmt.Scanln(&EgovEdcrNotification_EdcrSmsPassword)
	if EgovEdcrNotification_EdcrSmsPassword != "" {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrSmsPassword = EgovEdcrNotification_EdcrSmsPassword
	} else {
		sec.ClusterConfigs.Secrets.EgovEdcrNotification.EdcrSmsPassword = EdcrSmsPassword
	}
	fmt.Println("Enter Chatbot_ValuefirstUsername:")
	fmt.Scanln(&Chatbot_ValuefirstUsername)
	if Chatbot_ValuefirstUsername != "" {
		sec.ClusterConfigs.Secrets.Chatbot.ValuefirstUsername = Chatbot_ValuefirstUsername
	} else {
		sec.ClusterConfigs.Secrets.Chatbot.ValuefirstUsername = ValuefirstUsername
	}
	fmt.Println("Enter Chatbot_ValuefirstPassword:")
	fmt.Scanln(&Chatbot_ValuefirstPassword)
	if Chatbot_ValuefirstPassword != "" {
		sec.ClusterConfigs.Secrets.Chatbot.ValuefirstPassword = Chatbot_ValuefirstPassword
	} else {
		sec.ClusterConfigs.Secrets.Chatbot.ValuefirstPassword = ValuefirstPassword
	}
	fmt.Println("Enter EgovUserChatbot_CitizenLoginPasswordOtpFixedValue:")
	fmt.Scanln(&EgovUserChatbot_CitizenLoginPasswordOtpFixedValue)
	if EgovUserChatbot_CitizenLoginPasswordOtpFixedValue != "" {
		sec.ClusterConfigs.Secrets.EgovUserChatbot.CitizenLoginPasswordOtpFixedValue = EgovUserChatbot_CitizenLoginPasswordOtpFixedValue
	} else {
		sec.ClusterConfigs.Secrets.EgovUserChatbot.CitizenLoginPasswordOtpFixedValue = CitizenLoginPasswordOtpFixedValue
	}
	fmt.Println("Enter Oauth2Proxy_ClientID:")
	fmt.Scanln(&Oauth2Proxy_ClientID)
	if Oauth2Proxy_ClientID != "" {
		sec.ClusterConfigs.Secrets.Oauth2Proxy.ClientID = Oauth2Proxy_ClientID
	} else {
		sec.ClusterConfigs.Secrets.Oauth2Proxy.ClientID = ClientID
	}
	fmt.Println("Enter Oauth2Proxy_ClientSecret:")
	fmt.Scanln(&Oauth2Proxy_ClientSecret)
	if Oauth2Proxy_ClientSecret != "" {
		sec.ClusterConfigs.Secrets.Oauth2Proxy.ClientSecret = Oauth2Proxy_ClientSecret
	} else {
		sec.ClusterConfigs.Secrets.Oauth2Proxy.ClientSecret = ClientSecret
	}
	fmt.Println("Enter Oauth2Proxy_CookieSecret:")
	fmt.Scanln(&Oauth2Proxy_CookieSecret)
	if Oauth2Proxy_CookieSecret != "" {
		sec.ClusterConfigs.Secrets.Oauth2Proxy.CookieSecret = Oauth2Proxy_CookieSecret
	} else {
		sec.ClusterConfigs.Secrets.Oauth2Proxy.CookieSecret = CookieSecret
	}
	secretsmar, err := yaml.Marshal(&sec)
	if err != nil {
		log.Printf("%v", err)

	}
	secFilename := fmt.Sprintf("../../config-as-code/environments/%s-secrets.yaml", cluster_name)
	err = ioutil.WriteFile(secFilename, secretsmar, 0644)
	if err != nil {
		log.Printf("%v", err)
	}
}
