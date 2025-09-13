
class StateCollector {
    private client;
    private hookAbi;
    private hookAddress;
    private poolIds: [];

    async collectUserStrategies() {
        const strategies = {};
        for (let i = 1; i <= 9; i++) {
            const userAddress = this.getUserAddress(i);
            strategies[userAddress] = await this.client.readContract({
                address: this.hookAddress,
                abi: this.hookAbi,
                functionName: 'userStrategies',
                args: [userAddress]
            });
        }
        return strategies;
    }

    async collectPoolData() {
        const pools = {};
        for (const poolId of this.poolIds) {
            pools[poolId] = {
                strategy: await this.getPoolStrategy(poolId),
                activeUsers: await this.getActiveUsers(poolId),
                tvl: await this.calculateTVL(poolId)
            };
        }
        return pools;
    }
    getPoolStrategy(poolId: string) {

    }

    getActiveUsers(poolId: string) {

    }

    calculateTVL(poolId: number) {

    }

    getUserAddress(i: number) {

    }
}

export default StateCollector;
