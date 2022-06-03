test:
	forge test --fork-url=https://rpc.moonriver.moonbeam.network --match-contract=MultiRewardStratTest
test-vvv:
	forge test --fork-url=https://rpc.moonriver.moonbeam.network --match-contract=MultiRewardStratTest -vvv
test-ss:
	forge test --fork-url=https://rpc.moonriver.moonbeam.network --match-contract=SolarStrategyTest
test-mrs:
	forge test --fork-url=https://rpc.moonriver.moonbeam.network --match-contract=MultiRewardStratTest
