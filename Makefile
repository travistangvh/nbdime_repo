.PHONY: create_env activate_env remove_env test train predict data load_test

#################################################################################
# GLOBALS                                                                       #
#################################################################################

SHELL=/bin/bash
PROJECT_NAME = nbdime-env
PROJECT_DIR = $(shell pwd)
# TEST_ENV_DIR = ./env/test

ifeq (,$(shell which pyenv))
	HAS_PYENV=False
	CONDA_ROOT=$(shell conda info --root)
ifeq (True,$(shell if [ -d ${CONDA_ROOT}/envs/${PROJECT_NAME} ]; then echo True; fi))
	# use conda environment if available (when running on local)
	BINARIES = ${CONDA_ROOT}/envs/${PROJECT_NAME}/bin
else
	# use conda root if env is missing (when running on Docker)
	BINARIES = ${CONDA_ROOT}/bin
endif
else
	HAS_PYENV=True
	CONDA_VERSION=$(shell echo $(shell pyenv version | awk '{print $$1;}') | awk -F "/" '{print $$1}')
	BINARIES = $(HOME)/.pyenv/versions/${CONDA_VERSION}/envs/${PROJECT_NAME}/bin
endif

#################################################################################
# COMMANDS                                                                      #
#################################################################################

pip_conf:
	bash ./scripts/setup_pip_conf.sh

# required to build docker with xgboost
install_cmake:
	pwd
	cp Makefile Makefile_similarity_temp
	@echo "Uninstall cmake 3.13"
	apt-get remove cmake -y
	@echo ">>> downloading file"
	wget "https://cmake.org/files/v3.14/cmake-3.14.0.tar.gz" -P $$HOME/lib
	@echo ">>> creating directory for untarring file"
	(mkdir $$HOME/lib | echo "failed")
	mkdir $$HOME/lib/cmake-3.14.0
	mkdir $$HOME/opt
	mkdir $$HOME/opt/cmake
	@echo ">>> untarring file"
	tar -xf $$HOME/lib/cmake-3.14.0.tar.gz -C $$HOME/lib/cmake-3.14.0
	@echo "going into lib"
	cd $$HOME/lib
	@echo "configuring"
	$$HOME/lib/cmake-3.14.0/cmake-3.14.0/configure 
	@echo "making"
	make
	@echo "make installing"
	make install
	@echo "cd .."
	cd /builds/data-science/gomerchant/inca-maf-image-similarity
	@echo "install_cmake done"
	@echo "remove cmake's Makefile"
	rm Makefile
	@echo "add image-similaritys Makefile"
	cp Makefile_similarity_temp Makefile

## Set up conda environment and install dependencies
create_env:
ifeq (True,$(HAS_PYENV))
		@echo ">>> Detected pyenv, changing pyenv version."
		pyenv local ${CONDA_VERSION}
		conda update -n base -c defaults conda
		conda env create --name $(PROJECT_NAME) -f environment.yaml --force
		pyenv local ${CONDA_VERSION}/envs/${PROJECT_NAME}
else
		@echo ">>> Creating conda environment."
		conda update -n base -c defaults conda
	 	conda env create --name $(PROJECT_NAME) -f environment.yaml --force
	 	@echo ">>> Activating new conda environment"
	 	source $(CONDA_ROOT)/bin/activate $(PROJECT_NAME)
endif

remove_env:
ifeq (True,$(HAS_PYENV))
		@echo ">>> Detected pyenv, removing pyenv version."
		pyenv local ${CONDA_VERSION} && rm -rf ~/.pyenv/versions/${CONDA_VERSION}/envs/$(PROJECT_NAME)
else
		@echo ">>> Removing conda environemnt"
		conda remove -n $(PROJECT_NAME) --all
endif


## Activate conda environment
activate_env:
ifeq (True,$(HAS_PYENV))
		pyenv local ${CONDA_VERSION}/envs/${PROJECT_NAME}
else
		source $(CONDA_ROOT)/bin/activate $(PROJECT_NAME)
endif

test:
	bash ./test/test_runner.sh NOSETESTS_EXECUTABLE=${BINARIES}/nosetests

load_test:
	bash ./test/load_test.sh

# Build docker image
image:
	bash /builds/data-science/gomerchant/inca-maf-image-similarity/scripts/build_image.sh GCP_PROJECT=$(GCP_PROJECT) RELEASE_NAME=$(RELEASE_NAME) PUSH=$(PUSH)

## Train model
train:
	${BINARIES}/python -m src.models.make_train $(EXECUTION_DATE)

## Generate predictions
predict:
	${BINARIES}/python -m src.models.make_predict $(EXECUTION_DATE)

## Generate predictions
data:
	${BINARIES}/python -m src.data.make_data $(EXECUTION_DATE)

## Deploy
push-deploy-staging:
	${BINARIES}/python -m src.deploy.make_push staging false $(RUN_ID)

push-deploy-production:
	${BINARIES}/python -m src.deploy.make_push production false $(RUN_ID)

## Deploy and serve
push-deploy-serve-staging:
	${BINARIES}/python -m src.deploy.make_push staging true $(RUN_ID)

push-deploy-serve-production:
	${BINARIES}/python -m src.deploy.make_push production true $(RUN_ID)

## API tests
api_test:
	${BINARIES}/python -m test.post_deployment.post_deployment_api_test

api_test_local:
	${BINARIES}/python -m test.post_deployment.post_deployment_api_test


#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := show-help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: show-help
show-help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
