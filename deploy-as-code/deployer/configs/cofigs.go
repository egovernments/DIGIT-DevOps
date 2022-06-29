package configs

type Environment struct {
	Global struct {
		Domain string `yaml:"domain"`
		Setup  string `yaml:"setup"`
	} `yaml:"global"`
	ClusterConfigs struct {
		Namespaces struct {
			Create bool     `yaml:"create"`
			Values []string `yaml:"values"`
		} `yaml:"namespaces"`
		RootIngress struct {
			CertIssuer string `yaml:"cert-issuer"`
		} `yaml:"root-ingress"`
		Configmaps struct {
			EgovConfig struct {
				Data struct {
					DbHost                                string `yaml:"db-host"`
					DbName                                string `yaml:"db-name"`
					DbURL                                 string `yaml:"db-url"`
					Domain                                string `yaml:"domain"`
					EgovServicesFqdnName                  string `yaml:"egov-services-fqdn-name"`
					EgovStateLevelTenantID                string `yaml:"egov-state-level-tenant-id"`
					S3AssetsBucket                        string `yaml:"s3-assets-bucket"`
					EsHost                                string `yaml:"es-host"`
					EsIndexerHost                         string `yaml:"es-indexer-host"`
					FlywayLocations                       string `yaml:"flyway-locations"`
					KafkaBrokers                          string `yaml:"kafka-brokers"`
					KafkaInfraBrokers                     string `yaml:"kafka-infra-brokers"`
					LoggingLevelJdbc                      string `yaml:"logging-level-jdbc"`
					MobileValidationWorkaround            string `yaml:"mobile-validation-workaround"`
					SerializersTimezoneInIst              string `yaml:"serializers-timezone-in-ist"`
					ServerTomcatMaxConnections            string `yaml:"server-tomcat-max-connections"`
					ServerTomcatMaxThreads                string `yaml:"server-tomcat-max-threads"`
					SmsEnabled                            string `yaml:"sms-enabled"`
					SpringDatasourceTomcatInitialSize     string `yaml:"spring-datasource-tomcat-initialSize"`
					SpringDatasourceTomcatMaxActive       string `yaml:"spring-datasource-tomcat-max-active"`
					SpringJpaShowSQL                      string `yaml:"spring-jpa-show-sql"`
					Timezone                              string `yaml:"timezone"`
					TracerErrorsProvideexceptionindetails string `yaml:"tracer-errors-provideexceptionindetails"`
				} `yaml:"data"`
			} `yaml:"egov-config"`
			EgovServiceHost struct {
				Data struct {
					AssetServices           string `yaml:"asset-services"`
					AssetServicesMaha       string `yaml:"asset-services-maha"`
					BillingService          string `yaml:"billing-service"`
					CollectionServices      string `yaml:"collection-services"`
					CollectionMasters       string `yaml:"collection-masters"`
					CollectionSearchIndexer string `yaml:"collection-search-indexer"`
					CitizenIndexer          string `yaml:"citizen-indexer"`
					CitizenServices         string `yaml:"citizen-services"`
					DashboardAnalytics      string `yaml:"dashboard-analytics"`
					DashboardIngest         string `yaml:"dashboard-ingest"`
					DemandServices          string `yaml:"demand-services"`
					DataSyncEmployee        string `yaml:"data-sync-employee"`
					EgovCommonMasters       string `yaml:"egov-common-masters"`
					EgfMasters              string `yaml:"egf-masters"`
					EgfMaster               string `yaml:"egf-master"`
					EgfInstrument           string `yaml:"egf-instrument"`
					EgfVoucher              string `yaml:"egf-voucher"`
					EgfBill                 string `yaml:"egf-bill"`
					EgovEncService          string `yaml:"egov-enc-service"`
					EgfVoucherWorkflow      string `yaml:"egf-voucher-workflow"`
					EgovAccesscontrol       string `yaml:"egov-accesscontrol"`
					EgovUser                string `yaml:"egov-user"`
					EgovUserEgov            string `yaml:"egov-user-egov"`
					EgovLocation            string `yaml:"egov-location"`
					EgovFilestore           string `yaml:"egov-filestore"`
					EgovLocalization        string `yaml:"egov-localization"`
					EgovIdgen               string `yaml:"egov-idgen"`
					EgovOtp                 string `yaml:"egov-otp"`
					EgovCommonWorkflows     string `yaml:"egov-common-workflows"`
					EgovMdmsService         string `yaml:"egov-mdms-service"`
					EgovMdmsServiceTest     string `yaml:"egov-mdms-service-test"`
					EgovMdmsCreate          string `yaml:"egov-mdms-create"`
					EgovEis                 string `yaml:"egov-eis"`
					EgovWorkflow            string `yaml:"egov-workflow"`
					EgovWorkflowV2          string `yaml:"egov-workflow-v2"`
					EgovSearcher            string `yaml:"egov-searcher"`
					EgovDataUploader        string `yaml:"egov-data-uploader"`
					EgovIndexer             string `yaml:"egov-indexer"`
					EgovHrms                string `yaml:"egov-hrms"`
					EsClient                string `yaml:"es-client"`
					HrMasters               string `yaml:"hr-masters"`
					HrEmployee              string `yaml:"hr-employee"`
					HrMastersV2             string `yaml:"hr-masters-v2"`
					HrEmployeeV2            string `yaml:"hr-employee-v2"`
					HrAttendance            string `yaml:"hr-attendance"`
					HrLeave                 string `yaml:"hr-leave"`
					HrEmployeeMovement      string `yaml:"hr-employee-movement"`
					InventoryServices       string `yaml:"inventory-services"`
					LamsServices            string `yaml:"lams-services"`
					LcmsWorkflow            string `yaml:"lcms-workflow"`
					LcmsServices            string `yaml:"lcms-services"`
					Location                string `yaml:"location"`
					PerformanceAssessment   string `yaml:"performance-assessment"`
					PtProperty              string `yaml:"pt-property"`
					PtWorkflow              string `yaml:"pt-workflow"`
					PtTaxEnrichment         string `yaml:"pt-tax-enrichment"`
					PtCalculator            string `yaml:"pt-calculator"`
					PtCalculatorV2          string `yaml:"pt-calculator-v2"`
					PtServicesV2            string `yaml:"pt-services-v2"`
					PropertyServices        string `yaml:"property-services"`
					PgrMaster               string `yaml:"pgr-master"`
					PgrRest                 string `yaml:"pgr-rest"`
					PdfService              string `yaml:"pdf-service"`
					Report                  string `yaml:"report"`
					SwmServices             string `yaml:"swm-services"`
					Tenant                  string `yaml:"tenant"`
					TlMasters               string `yaml:"tl-masters"`
					TlServices              string `yaml:"tl-services"`
					TlWorkflow              string `yaml:"tl-workflow"`
					TlIndexer               string `yaml:"tl-indexer"`
					TlCalculator            string `yaml:"tl-calculator"`
					UserOtp                 string `yaml:"user-otp"`
					FirenocServices         string `yaml:"firenoc-services"`
					FirenocCalculator       string `yaml:"firenoc-calculator"`
					EgovApportionService    string `yaml:"egov-apportion-service"`
					BpaServices             string `yaml:"bpa-services"`
					BpaCalculator           string `yaml:"bpa-calculator"`
					RainmakerPgr            string `yaml:"rainmaker-pgr"`
					WsCalculator            string `yaml:"ws-calculator"`
					WsServices              string `yaml:"ws-services"`
					SwServices              string `yaml:"sw-services"`
					SwCalculator            string `yaml:"sw-calculator"`
					LandServices            string `yaml:"land-services"`
					NocServices             string `yaml:"noc-services"`
					MinioURL                string `yaml:"minio-url"`
					EgovUserChatbot         string `yaml:"egov-user-chatbot"`
					Zuul                    string `yaml:"zuul"`
					EgovURLShortening       string `yaml:"egov-url-shortening"`
					FsmCalculator           string `yaml:"fsm-calculator"`
					Fsm                     string `yaml:"fsm"`
					Vehicle                 string `yaml:"vehicle"`
					Vendor                  string `yaml:"vendor"`
					EgovEdcr                string `yaml:"egov-edcr"`
					EchallanCalculator      string `yaml:"echallan-calculator"`
					EchallanServices        string `yaml:"echallan-services"`
					Inbox                   string `yaml:"inbox"`
					TurnIoAdapter           string `yaml:"turn-io-adapter"`
					PgrServices             string `yaml:"pgr-services"`
					BirthDeathServices      string `yaml:"birth-death-services"`
					EgovPdf                 string `yaml:"egov-pdf"`
				} `yaml:"data"`
			} `yaml:"egov-service-host"`
		} `yaml:"configmaps"`
	} `yaml:"cluster-configs"`
	EgovFilestore struct {
		Volume                string `yaml:"volume"`
		IsBucketFixed         string `yaml:"is-bucket-fixed"`
		MinioURL              string `yaml:"minio.url"`
		AwsS3URL              string `yaml:"aws.s3.url"`
		IsS3Enabled           string `yaml:"is-s3-enabled"`
		MinioEnabled          bool   `yaml:"minio-enabled"`
		AllowedFileFormatsMap string `yaml:"allowed-file-formats-map"`
		AllowedFileFormats    string `yaml:"allowed-file-formats"`
		FilestoreURLValidity  int    `yaml:"filestore-url-validity"`
		FixedBucketname       string `yaml:"fixed-bucketname"`
	} `yaml:"egov-filestore"`
	EgovIdgen struct {
		IdformatFromMdms string `yaml:"idformat-from-mdms"`
	} `yaml:"egov-idgen"`
	EgovNotificationSms struct {
		SmsProviderURL                   string `yaml:"sms-provider-url"`
		SmsProviderClass                 string `yaml:"sms.provider.class"`
		SmsProviderContentType           string `yaml:"sms.provider.contentType"`
		SmsConfigMap                     string `yaml:"sms-config-map"`
		SmsGatewayToUse                  string `yaml:"sms-gateway-to-use"`
		SmsSender                        string `yaml:"sms-sender"`
		SmsSenderRequesttype             string `yaml:"sms-sender-requesttype"`
		SmsCustomConfig                  string `yaml:"sms-custom-config"`
		SmsExtraReqParams                string `yaml:"sms-extra-req-params"`
		SmsSenderReqParamName            string `yaml:"sms-sender-req-param-name"`
		SmsSenderUsernameReqParamName    string `yaml:"sms-sender-username-req-param-name"`
		SmsSenderPasswordReqParamName    string `yaml:"sms-sender-password-req-param-name"`
		SmsDestinationMobileReqParamName string `yaml:"sms-destination-mobile-req-param-name"`
		SmsMessageReqParamName           string `yaml:"sms-message-req-param-name"`
		SmsErrorCodes                    string `yaml:"sms-error-codes"`
	} `yaml:"egov-notification-sms"`
	Chatbot struct {
		KafkaTopicsPartitionCount                  int    `yaml:"kafka-topics-partition-count"`
		KafkaTopicsReplicationFactor               int    `yaml:"kafka-topics-replication-factor"`
		KafkaConsumerPollMs                        int    `yaml:"kafka-consumer-poll-ms"`
		KafkaProducerLingerMs                      int    `yaml:"kafka-producer-linger-ms"`
		ContactCardWhatsappNumber                  string `yaml:"contact-card-whatsapp-number"`
		ContactCardWhatsappName                    string `yaml:"contact-card-whatsapp-name"`
		ValuefirstWhatsappNumber                   string `yaml:"valuefirst-whatsapp-number"`
		ValuefirstNotificationAssignedTemplateid   string `yaml:"valuefirst-notification-assigned-templateid"`
		ValuefirstNotificationResolvedTemplateid   string `yaml:"valuefirst-notification-resolved-templateid"`
		ValuefirstNotificationRejectedTemplateid   string `yaml:"valuefirst-notification-rejected-templateid"`
		ValuefirstNotificationReassignedTemplateid string `yaml:"valuefirst-notification-reassigned-templateid"`
		ValuefirstNotificationCommentedTemplateid  string `yaml:"valuefirst-notification-commented-templateid"`
		ValuefirstNotificationWelcomeTemplateid    string `yaml:"valuefirst-notification-welcome-templateid"`
		ValuefirstNotificationRootTemplateid       string `yaml:"valuefirst-notification-root-templateid"`
		ValuefirstSendMessageURL                   string `yaml:"valuefirst-send-message-url"`
		UserServiceChatbotCitizenPasswrord         string `yaml:"user-service-chatbot-citizen-passwrord"`
	} `yaml:"chatbot"`
	EgovMdmsService struct {
		Replicas       int      `yaml:"replicas"`
		Images         []string `yaml:"images"`
		MdmsPath       string   `yaml:"mdms-path"`
		InitContainers struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
		MdmsFolder       string `yaml:"mdms-folder"`
		MastersConfigURL string `yaml:"masters-config-url"`
		JavaArgs         string `yaml:"java-args"`
	} `yaml:"egov-mdms-service"`
	EgovIndexer struct {
		Heap           string `yaml:"heap"`
		MemoryLimits   string `yaml:"memory_limits"`
		InitContainers struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
		EgovIndexerYamlRepoPath string `yaml:"egov-indexer-yaml-repo-path"`
	} `yaml:"egov-indexer"`
	EgovPersister struct {
		Replicas       int      `yaml:"replicas"`
		Images         []string `yaml:"images"`
		PersistYmlPath string   `yaml:"persist-yml-path"`
		InitContainers struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
	} `yaml:"egov-persister"`
	EgovDataUploader struct {
		InitContainers struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
	} `yaml:"egov-data-uploader"`
	EgovSearcher struct {
		SearchYamlPath string `yaml:"search-yaml-path"`
		InitContainers struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
	} `yaml:"egov-searcher"`
	EgovCustomConsumer struct {
		ErpHost string `yaml:"erp-host"`
	} `yaml:"egov-custom-consumer"`
	EgfMaster struct {
		DbURL        string `yaml:"db-url"`
		MemoryLimits string `yaml:"memory_limits"`
		Heap         string `yaml:"heap"`
	} `yaml:"egf-master"`
	Redoc struct {
		Replicas    int      `yaml:"replicas"`
		Images      []string `yaml:"images"`
		ServiceType string   `yaml:"service_type"`
	} `yaml:"redoc"`
	NginxIngress struct {
		Images                []string `yaml:"images"`
		Replicas              int      `yaml:"replicas"`
		DefaultBackendService string   `yaml:"default-backend-service"`
		Namespace             string   `yaml:"namespace"`
		CertIssuer            string   `yaml:"cert-issuer"`
		SslProtocols          string   `yaml:"ssl-protocols"`
		SslCiphers            string   `yaml:"ssl-ciphers"`
		SslEcdhCurve          string   `yaml:"ssl-ecdh-curve"`
	} `yaml:"nginx-ingress"`
	CertManager struct {
		Email     string   `yaml:"email"`
		Images    []string `yaml:"images"`
		Namespace string   `yaml:"namespace"`
	} `yaml:"cert-manager"`
	Zuul struct {
		Replicas                        int    `yaml:"replicas"`
		CustomFilterProperty            string `yaml:"custom-filter-property"`
		TracingEnabled                  string `yaml:"tracing-enabled"`
		Heap                            string `yaml:"heap"`
		ServerTomcatMaxThreads          string `yaml:"server-tomcat-max-threads"`
		ServerTomcatMaxConnections      string `yaml:"server-tomcat-max-connections"`
		EgovOpenEndpointsWhitelist      string `yaml:"egov-open-endpoints-whitelist"`
		EgovMixedModeEndpointsWhitelist string `yaml:"egov-mixed-mode-endpoints-whitelist"`
	} `yaml:"zuul"`
	CollectionReceiptVoucherConsumer struct {
		JalandharErpHost string `yaml:"jalandhar-erp-host"`
		MohaliErpHost    string `yaml:"mohali-erp-host"`
		NayagaonErpHost  string `yaml:"nayagaon-erp-host"`
		AmritsarErpHost  string `yaml:"amritsar-erp-host"`
		KhararErpHost    string `yaml:"kharar-erp-host"`
		ZirakpurErpHost  string `yaml:"zirakpur-erp-host"`
	} `yaml:"collection-receipt-voucher-consumer"`
	FinanceCollectionsVoucherConsumer struct {
		ErpEnvName    string `yaml:"erp-env-name"`
		ErpDomainName string `yaml:"erp-domain-name"`
	} `yaml:"finance-collections-voucher-consumer"`
	DigitUI struct {
		CustomJsInjection string `yaml:"custom-js-injection"`
	} `yaml:"digit-ui"`
	Employee struct {
		CustomJsInjection string `yaml:"custom-js-injection"`
	} `yaml:"employee"`
	DashboardAnalytics struct {
		ConfigSchemaPaths string `yaml:"config-schema-paths"`
		InitContainers    struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
	} `yaml:"dashboard-analytics"`
	DashboardIngest struct {
		ConfigSchemaPaths string `yaml:"config-schema-paths"`
		InitContainers    struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
	} `yaml:"dashboard-ingest"`
	Citizen struct {
		CustomJsInjection string `yaml:"custom-js-injection"`
	} `yaml:"citizen"`
	Report struct {
		Heap                            string `yaml:"heap"`
		TracingEnabled                  string `yaml:"tracing-enabled"`
		SpringDatasourceTomcatMaxActive int    `yaml:"spring-datasource-tomcat-max-active"`
		InitContainers                  struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
		ReportLocationsfilePath string `yaml:"report-locationsfile-path"`
	} `yaml:"report"`
	PdfService struct {
		InitContainers struct {
			GitSync struct {
				Repo   string `yaml:"repo"`
				Branch string `yaml:"branch"`
			} `yaml:"gitSync"`
		} `yaml:"initContainers"`
		DataConfigUrls   string `yaml:"data-config-urls"`
		FormatConfigUrls string `yaml:"format-config-urls"`
	} `yaml:"pdf-service"`
	KafkaV2 struct {
		Persistence struct {
			Enabled bool `yaml:"enabled"`
			Aws     []struct {
				VolumeID string `yaml:"volumeId"`
				Zone     string `yaml:"zone"`
			} `yaml:"aws"`
		} `yaml:"persistence"`
		ZookeeperHosts           string `yaml:"zookeeperHosts"`
		HeapOptions              string `yaml:"heapOptions"`
		MemoryLimits             string `yaml:"memory_limits"`
		LingerMs                 string `yaml:"lingerMs"`
		NumberPartitions         string `yaml:"numberPartitions"`
		ReplicationFactor        string `yaml:"replicationFactor"`
		MinInsyncReplicas        string `yaml:"minInsyncReplicas"`
		OffsetsReplicationFactor string `yaml:"offsetsReplicationFactor"`
	} `yaml:"kafka-v2"`
	ZookeeperV2 struct {
		Persistence struct {
			Enabled bool `yaml:"enabled"`
			Aws     []struct {
				VolumeID string `yaml:"volumeId"`
				Zone     string `yaml:"zone"`
			} `yaml:"aws"`
		} `yaml:"persistence"`
		HeapOptions string `yaml:"heapOptions"`
		Resources   struct {
			Limits struct {
				CPU    string `yaml:"cpu"`
				Memory string `yaml:"memory"`
			} `yaml:"limits"`
			Requests struct {
				CPU    string `yaml:"cpu"`
				Memory string `yaml:"memory"`
			} `yaml:"requests"`
		} `yaml:"resources"`
	} `yaml:"zookeeper-v2"`
	ElasticsearchDataV1 struct {
		Image struct {
			Tag string `yaml:"tag"`
		} `yaml:"image"`
		Persistence struct {
			Enabled bool `yaml:"enabled"`
			Aws     []struct {
				VolumeID string `yaml:"volumeId"`
				Zone     string `yaml:"zone"`
			} `yaml:"aws"`
		} `yaml:"persistence"`
		EsJavaOpts string `yaml:"esJavaOpts"`
		Resources  struct {
			Requests struct {
				Memory string `yaml:"memory"`
			} `yaml:"requests"`
			Limits struct {
				Memory string `yaml:"memory"`
			} `yaml:"limits"`
		} `yaml:"resources"`
	} `yaml:"elasticsearch-data-v1"`
	ElasticsearchMasterV1 struct {
		Replicas int `yaml:"replicas"`
		Image    struct {
			Tag string `yaml:"tag"`
		} `yaml:"image"`
		Persistence struct {
			Enabled bool `yaml:"enabled"`
			Aws     []struct {
				VolumeID string `yaml:"volumeId"`
				Zone     string `yaml:"zone"`
			} `yaml:"aws"`
		} `yaml:"persistence"`
		EsJavaOpts string `yaml:"esJavaOpts"`
		Resources  struct {
			Requests struct {
				Memory string `yaml:"memory"`
			} `yaml:"requests"`
			Limits struct {
				Memory string `yaml:"memory"`
			} `yaml:"limits"`
		} `yaml:"resources"`
	} `yaml:"elasticsearch-master-v1"`
	EsCurator struct {
		Schedule             string   `yaml:"schedule"`
		Images               []string `yaml:"images"`
		EsHost               string   `yaml:"es-host"`
		LogsCleanupEnabled   string   `yaml:"logs-cleanup-enabled"`
		JaegerCleanupEnabled string   `yaml:"jaeger-cleanup-enabled"`
		LogsToRetain         string   `yaml:"logs-to-retain"`
	} `yaml:"es-curator"`
}
