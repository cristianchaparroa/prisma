# make contract=YieldMaximizerHook generate-abi
generate-abi:
	forge build
	jq .abi 'out/$(contract).sol/$(contract).json' > 'web/src/abi/$(contract).abi.json'
	@echo "Generating TypeScript ABI..."
	@printf "export const $(contract)ABI = " > 'web/src/abi/$(contract).abi.ts'
	@jq --indent 2 -r .abi 'out/$(contract).sol/$(contract).json' | tr -d '\n' >> 'web/src/abi/$(contract).abi.ts'
	@printf " as const;\n" >> 'web/src/abi/$(contract).abi.ts'
	@echo "Generated TypeScript ABI: web/src/abi/$(contract).abi.ts"

.PHONY: generate-abi

# Generate ABIs for all contracts in the out directory
generate-all-abis:
	forge build
	@mkdir -p web/src/generated
	@find out -name "*.json" -type f | while read -r file; do \
		contract_name=$$(basename "$$file" .json); \
		echo "Generating ABI for $$contract_name"; \
		jq .abi "$$file" > "web/src/generated/$$contract_name.abi.json"; \
	done
	@echo "All ABI files generated in web/src/generated/"

.PHONY: generate-abi generate-all-abis
