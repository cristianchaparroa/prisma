import { useState, useEffect } from "react";
import { ethers } from "ethers";
import { ArrowDownUp } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";

// Universal Router and Permit2 Addresses (Mainnet addresses since we're forking mainnet)
const UNIVERSAL_ROUTER_ADDRESS = "0x66a9893cc07d91d95644aedd05d03f95e1dba8af";
const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

// Anvil default configuration
const ANVIL_RPC_URL = "http://127.0.0.1:8545";
const ANVIL_CHAIN_ID = 31337;

// ERC20 ABI (for approve function)
const ERC20_ABI = [
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function balanceOf(address account) external view returns (uint256)",
    "function decimals() external view returns (uint8)",
    "function symbol() external view returns (string)",
];

// Permit2 ABI
const PERMIT2_ABI = [
    "function approve(address token, address spender, uint160 amount, uint48 expiration) external",
];

// Router ABI
const ROUTER_ABI = ["function execute(bytes calldata commands, bytes[] calldata inputs) public payable"];

export const SUPPORTED_TOKENS = {
    USDC: {
        address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        symbol: "USDC",
        name: "USD Coin",
        decimals: 6,
        iconUrl: "https://assets.coingecko.com/coins/images/6319/small/usdc.png",
    },
    WETH: {
        address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        symbol: "WETH",
        name: "Wrapped Ether",
        decimals: 18,
        iconUrl: "https://assets.coingecko.com/coins/images/2518/small/weth.png",
    },
    DAI: {
        address: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        symbol: "DAI",
        name: "Dai Stablecoin",
        decimals: 18,
        iconUrl: "https://assets.coingecko.com/coins/images/9956/small/Badge_Dai.png",
    },
    USDT: {
        address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        symbol: "USDT",
        name: "Tether USD",
        decimals: 6,
        iconUrl: "https://assets.coingecko.com/coins/images/325/small/Tether.png",
    },
    WBTC: {
        address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        symbol: "WBTC",
        name: "Wrapped Bitcoin",
        decimals: 8,
        iconUrl: "https://assets.coingecko.com/coins/images/7598/small/wrapped_bitcoin_wbtc.png",
    },
};

export const TOKEN_LIST = Object.values(SUPPORTED_TOKENS);

export const getTokenByAddress = (address) => {
    return TOKEN_LIST.find((t) => t.address.toLowerCase() === address.toLowerCase());
};

function SwapComponent() {
    const [tokenIn, setTokenIn] = useState(SUPPORTED_TOKENS.WETH.address);
    const [tokenOut, setTokenOut] = useState(SUPPORTED_TOKENS.USDC.address);
    const [amount, setAmount] = useState("1000000");
    const [provider, setProvider] = useState(null);
    const [signer, setSigner] = useState(null);
    const [currentAccount, setCurrentAccount] = useState(null);
    const [availableAccounts, setAvailableAccounts] = useState([]);
    const [isConnected, setIsConnected] = useState(false);
    const [connectionError, setConnectionError] = useState(null);
    const [tokenInBalance, setTokenInBalance] = useState(null);
    const [tokenOutBalance, setTokenOutBalance] = useState(null);

    useEffect(() => {
        connectToAnvil();
    }, []);

    useEffect(() => {
        if (signer && currentAccount) {
            loadTokenBalances(signer, currentAccount);
        }
    }, [tokenIn, tokenOut, signer, currentAccount]);

    const switchToAnvilNetwork = async () => {
        if (!window.ethereum) return;

        try {
            // Try to switch to Anvil network
            await window.ethereum.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: `0x${ANVIL_CHAIN_ID.toString(16)}` }], // Convert to hex
            });
        } catch (switchError) {
            // If network doesn't exist, add it
            if (switchError.code === 4902) {
                try {
                    await window.ethereum.request({
                        method: 'wallet_addEthereumChain',
                        params: [{
                            chainId: `0x${ANVIL_CHAIN_ID.toString(16)}`,
                            chainName: 'Anvil Local',
                            nativeCurrency: {
                                name: 'Ethereum',
                                symbol: 'ETH',
                                decimals: 18,
                            },
                            rpcUrls: [ANVIL_RPC_URL],
                        }],
                    });
                } catch (addError) {
                    throw new Error('Failed to add Anvil network to MetaMask');
                }
            } else {
                throw switchError;
            }
        }
    };

    const connectToAnvil = async () => {
        try {
            setConnectionError(null);

            // Check if MetaMask is available
            if (!window.ethereum) {
                throw new Error("Please install MetaMask");
            }

            // First, let's check and switch network if needed
            const tempProvider = new ethers.providers.Web3Provider(window.ethereum);
            const currentNetwork = await tempProvider.getNetwork();

            if (currentNetwork.chainId !== ANVIL_CHAIN_ID) {
                console.log(`Wrong network detected (${currentNetwork.chainId}), switching to Anvil...`);
                await switchToAnvilNetwork();

                // Wait a bit for the network to switch
                await new Promise(resolve => setTimeout(resolve, 1000));
            }

            // Create a fresh provider after network switch
            const _provider = new ethers.providers.Web3Provider(window.ethereum);

            // Request account access and get ALL available accounts
            await _provider.send("eth_requestAccounts", []);
            const accounts = await _provider.send("eth_accounts", []);

            // Get the network to verify it's Anvil
            const network = await _provider.getNetwork();
            console.log("Connected to network:", network);

            // Final check - if still wrong network, throw error
            if (network.chainId !== ANVIL_CHAIN_ID) {
                throw new Error(`Still on wrong network! Chain ID: ${network.chainId}. Please manually switch to Anvil network (Chain ID: ${ANVIL_CHAIN_ID}) in MetaMask.`);
            }

            // Use the first account as default
            const defaultAccount = accounts[0];
            const _signer = _provider.getSigner(defaultAccount);

            console.log("Successfully connected:", { chainId: network.chainId, accounts });

            setProvider(_provider);
            setSigner(_signer);
            setCurrentAccount(defaultAccount);
            setAvailableAccounts(accounts);
            setIsConnected(true);
            await loadTokenBalances(_signer, defaultAccount);
        } catch (error) {
            console.error("Failed to connect to MetaMask:", error);
            setConnectionError(error?.message || String(error));
            setIsConnected(false);
        }
    };

    const loadTokenBalances = async (signer, address) => {
        try {
            const tokenInContract = new ethers.Contract(tokenIn, ERC20_ABI, signer);
            const balanceIn = await tokenInContract.balanceOf(address);
            const decimalsIn = await tokenInContract.decimals();
            const symbolIn = await tokenInContract.symbol();

            const tokenOutContract = new ethers.Contract(tokenOut, ERC20_ABI, signer);
            const balanceOut = await tokenOutContract.balanceOf(address);
            const decimalsOut = await tokenOutContract.decimals();
            const symbolOut = await tokenOutContract.symbol();

            setTokenInBalance({
                balance: ethers.utils.formatUnits(balanceIn, decimalsIn),
                symbol: symbolIn,
                decimals: decimalsIn,
            });

            setTokenOutBalance({
                balance: ethers.utils.formatUnits(balanceOut, decimalsOut),
                symbol: symbolOut,
                decimals: decimalsOut,
            });
        } catch (error) {
            console.error("Error loading token balances:", error);
            setTokenInBalance({ balance: "0", symbol: getTokenByAddress(tokenIn)?.symbol || "" });
            setTokenOutBalance({ balance: "0", symbol: getTokenByAddress(tokenOut)?.symbol || "" });
        }
    };

    const approveToken = async () => {
        if (!signer || !tokenIn) {
            alert("Connect to Anvil and enter token address");
            return;
        }

        try {
            const tokenContract = new ethers.Contract(tokenIn, ERC20_ABI, signer);
            const permit2Contract = new ethers.Contract(PERMIT2_ADDRESS, PERMIT2_ABI, signer);
            const decimals = await tokenContract.decimals();
            const maxApproval = ethers.utils.parseUnits("1000000000", decimals);

            const tx1 = await tokenContract.approve(PERMIT2_ADDRESS, maxApproval);
            await tx1.wait();

            const expiration = Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 7;
            const tx2 = await permit2Contract.approve(
                tokenIn,
                UNIVERSAL_ROUTER_ADDRESS,
                maxApproval,
                expiration
            );
            await tx2.wait();
            alert("Token approval successful!");
            if (signer && currentAccount) await loadTokenBalances(signer, currentAccount);
        } catch (error) {
            console.error("Approval error:", error);
            alert(`Approval failed: ${error?.message || String(error)}`);
        }
    };

    const swapTokens = async () => {
        if (!signer || !tokenIn || !tokenOut || !amount) {
            alert("Fill all fields and ensure Anvil connection");
            return;
        }

        const router = new ethers.Contract(UNIVERSAL_ROUTER_ADDRESS, ROUTER_ABI, signer);
        
        // Get token decimals to format amount properly
        const tokenInContract = new ethers.Contract(tokenIn, ERC20_ABI, signer);
        const decimalsIn = await tokenInContract.decimals();
        
        // Convert human-readable amount to base units (20 USDC -> 20000000)
        const amountInBaseUnits = ethers.utils.parseUnits(amount, decimalsIn);
        
        const poolKey = {
            currency0: tokenIn,
            currency1: tokenOut,
            fee: 3000,
            tickSpacing: 60,
            hooks: "0x515b8cB454d140d32262a95d758Ec51D5ed3d540",
        };
        const commands = ethers.utils.solidityPack(["uint8"], [0x10]);
        const actions = ethers.utils.solidityPack(["uint8", "uint8", "uint8"], [0x06, 0x0C, 0x0F]);
        const exactInputSingleParams = ethers.utils.defaultAbiCoder.encode(
            [
                "tuple(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, bool zeroForOne, uint128 amountIn, uint128 amountOutMinimum, bytes hookData)"
            ],
            [
                {
                    poolKey,
                    zeroForOne: true,
                    amountIn: amountInBaseUnits,  // Use properly formatted amount
                    amountOutMinimum: ethers.BigNumber.from(0),
                    hookData: "0x",
                },
            ]
        );
        const params = [
            exactInputSingleParams,
            ethers.utils.defaultAbiCoder.encode(["address", "uint128"], [poolKey.currency0, amountInBaseUnits]),  // Use properly formatted amount
            ethers.utils.defaultAbiCoder.encode(["address", "uint128"], [poolKey.currency1, 0]),
        ];
        const inputs = [ethers.utils.defaultAbiCoder.encode(["bytes", "bytes[]"], [actions, params])];

        try {
            const tx = await router.execute(commands, inputs, { value: 0 });
            await tx.wait();
            alert("Swap executed successfully!");
            if (signer && currentAccount) await loadTokenBalances(signer, currentAccount);
        } catch (error) {
            console.error("Swap error:", error);
            alert(`Swap failed: ${error?.message || String(error)}`);
        }
    };

    const disconnectWallet = () => {
        setProvider(null);
        setSigner(null);
        setCurrentAccount(null);
        setAvailableAccounts([]);
        setIsConnected(false);
        setConnectionError(null);
        setTokenInBalance(null);
        setTokenOutBalance(null);
        console.log("Wallet disconnected");
    };

    const switchAccount = async (newAccount) => {
        if (!provider || !availableAccounts.includes(newAccount)) {
            return;
        }
        
        try {
            // Create new signer for the selected account
            const _signer = provider.getSigner(newAccount);
            
            setSigner(_signer);
            setCurrentAccount(newAccount);
            await loadTokenBalances(_signer, newAccount);
            
            console.log("Switched to account:", newAccount);
        } catch (error) {
            console.error("Failed to switch account:", error);
            setConnectionError(error?.message || String(error));
        }
    };

    const requestAccountAccess = async () => {
        if (!window.ethereum || !provider) return;
        
        try {
            // Request account access and get ALL available accounts
            await provider.send("eth_requestAccounts", []);
            const accounts = await provider.send("eth_accounts", []);
            setAvailableAccounts(accounts);
            
            if (accounts.length > 0 && !currentAccount) {
                const defaultAccount = accounts[0];
                const _signer = provider.getSigner(defaultAccount);
                setSigner(_signer);
                setCurrentAccount(defaultAccount);
                await loadTokenBalances(_signer, defaultAccount);
            }
        } catch (error) {
            console.error("Failed to get accounts:", error);
        }
    };

    const handleTokenInChange = (newTokenIn) => {
        // If trying to set same token as tokenOut, swap them
        if (newTokenIn === tokenOut) {
            setTokenOut(tokenIn);
        }
        setTokenIn(newTokenIn);
    };

    const handleTokenOutChange = (newTokenOut) => {
        // If trying to set same token as tokenIn, swap them
        if (newTokenOut === tokenIn) {
            setTokenIn(tokenOut);
        }
        setTokenOut(newTokenOut);
    };

    const swapTokenPositions = () => {
        const tempTokenIn = tokenIn;
        setTokenIn(tokenOut);
        setTokenOut(tempTokenIn);

        // Also swap the amount to the opposite field if needed
        // This gives better UX
    };

    const refreshConnection = () => {
        setIsConnected(false);
        setConnectionError(null);
        connectToAnvil();
    };

    const currentInToken = getTokenByAddress(tokenIn);
    const currentOutToken = getTokenByAddress(tokenOut);

    return (
        <Card className="w-full max-w-md mx-auto p-6 bg-gray-900 text-white rounded-3xl shadow-xl">
            <CardHeader className="p-0 mb-6">
                <CardTitle className="text-3xl font-bold text-center text-gray-100">Uniswap v4 Swap</CardTitle>
                <CardDescription className="text-center text-gray-400">
                    Connect MetaMask to your Anvil testnet.
                </CardDescription>
            </CardHeader>

            <CardContent className="p-0 space-y-4">
                {/* Connection Status */}
                <div className="p-4 rounded-xl bg-gray-800 border border-gray-700">
                    <div className="flex items-center justify-between">
                        <span className="text-sm font-medium text-gray-400">MetaMask Connection:</span>
                        <div className="flex items-center space-x-2">
                            <div className={`w-3 h-3 rounded-full ${isConnected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></div>
                            <span className={`text-sm font-medium ${isConnected ? 'text-green-400' : 'text-red-400'}`}>
                                {isConnected ? 'Connected' : 'Disconnected'}
                            </span>
                        </div>
                    </div>
                    {isConnected && (
                        <div className="mt-2 text-sm text-gray-500">
                            <div className="truncate">Network: Anvil (Chain ID: {ANVIL_CHAIN_ID})</div>
                            <div className="flex items-center justify-between">
                                <span>Account: </span>
                                <div className="flex items-center space-x-2">
                                    <span className="font-mono text-xs text-gray-400">
                                        {currentAccount?.slice(0, 6)}...{currentAccount?.slice(-4)}
                                    </span>
                                    {/* Show dropdown if we have multiple accounts */}
                                    {availableAccounts && availableAccounts.length > 1 && (
                                        <Select onValueChange={switchAccount} value={currentAccount}>
                                            <SelectTrigger className="w-20 h-6 bg-gray-700 border-gray-600 text-xs p-1">
                                                <SelectValue placeholder="Switch" />
                                            </SelectTrigger>
                                            <SelectContent className="bg-gray-800 text-white">
                                                {availableAccounts.map((account, index) => (
                                                    <SelectItem key={account} value={account} className="text-xs">
                                                        {account === '0x8611C17eA68caE77762AdF6446a00f5a71dd7784' ? 'Account 1' : 
                                                         account === '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' ? 'Account 2 (Anvil)' :
                                                         `Account ${index + 1}`}
                                                    </SelectItem>
                                                ))}
                                            </SelectContent>
                                        </Select>
                                    )}
                                </div>
                            </div>
                        </div>
                    )}
                    {connectionError && (
                        <div className="mt-2 p-2 bg-red-900 border border-red-700 rounded text-sm text-red-300">
                            <span className="font-semibold">Error:</span> {connectionError}
                        </div>
                    )}
                    {!isConnected && (
                        <Button onClick={refreshConnection} className="mt-4 w-full" variant="outline">
                            Connect MetaMask
                        </Button>
                    )}
                    {isConnected && (
                        <div className="mt-4 flex gap-2">
                            <Button onClick={refreshConnection} className="flex-1" variant="outline">
                                Reconnect
                            </Button>
                            <Button onClick={disconnectWallet} className="flex-1" variant="destructive">
                                Disconnect
                            </Button>
                        </div>
                    )}
                </div>

                {/* Swap Inputs */}
                <div className="space-y-4">
                    {/* Token In */}
                    <div className="bg-gray-800 rounded-xl p-4 border border-gray-700">
                        <Label htmlFor="tokenIn" className="text-xs text-gray-400">You Pay</Label>
                        <div className="flex items-center justify-between mt-1">
                            <div className="flex items-center space-x-2">
                                <img
                                    src={currentInToken?.iconUrl}
                                    alt={currentInToken?.symbol}
                                    className="w-8 h-8 rounded-full"
                                />
                                <Select onValueChange={handleTokenInChange} value={tokenIn}>
                                    <SelectTrigger className="w-[150px] bg-gray-700 border-gray-600">
                                        <SelectValue placeholder="Select Token" />
                                    </SelectTrigger>
                                    <SelectContent className="bg-gray-800 text-white">
                                        {TOKEN_LIST.map((token) => (
                                            <SelectItem key={token.address} value={token.address}>
                                                {token.symbol}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>
                            <Input
                                id="amount"
                                type="number"
                                placeholder="0.0"
                                value={amount}
                                onChange={(e) => setAmount(e.target.value)}
                                className="w-32 bg-gray-700 text-right text-lg font-bold border-gray-600 placeholder-gray-500 focus:border-indigo-500 focus:ring-indigo-500"
                            />
                        </div>
                        <div className="text-xs text-gray-500 mt-2 text-right">
                            Balance: {tokenInBalance ? Number(tokenInBalance.balance).toFixed(6) : '0.00'}
                        </div>
                    </div>

                    {/* Swap Icon */}
                    <div className="flex justify-center">
                        <div
                            onClick={swapTokenPositions}
                            className="p-2 bg-gray-700 rounded-full border-4 border-gray-900 shadow-lg cursor-pointer transform hover:rotate-180 transition-transform duration-300 hover:bg-gray-600"
                        >
                            <ArrowDownUp className="w-5 h-5 text-white" />
                        </div>
                    </div>

                    {/* Token Out */}
                    <div className="bg-gray-800 rounded-xl p-4 border border-gray-700">
                        <Label htmlFor="tokenOut" className="text-xs text-gray-400">You Receive</Label>
                        <div className="flex items-center justify-between mt-1">
                            <div className="flex items-center space-x-2">
                                <img
                                    src={currentOutToken?.iconUrl}
                                    alt={currentOutToken?.symbol}
                                    className="w-8 h-8 rounded-full"
                                />
                                <Select onValueChange={handleTokenOutChange} value={tokenOut}>
                                    <SelectTrigger className="w-[150px] bg-gray-700 border-gray-600">
                                        <SelectValue placeholder="Select Token" />
                                    </SelectTrigger>
                                    <SelectContent className="bg-gray-800 text-white">
                                        {TOKEN_LIST.map((token) => (
                                            <SelectItem key={token.address} value={token.address}>
                                                {token.symbol}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>
                            <div className="w-32 text-right text-lg font-bold text-gray-400">
                                0.00
                            </div>
                        </div>
                        <div className="text-xs text-gray-500 mt-2 text-right">
                            Balance: {tokenOutBalance ? Number(tokenOutBalance.balance).toFixed(6) : '0.00'}
                        </div>
                    </div>
                </div>

                {/* Action Buttons */}
                <div className="space-y-3 pt-2">
                    <Button
                        onClick={approveToken}
                        disabled={!isConnected}
                        className="bg-green-600 hover:bg-green-700 disabled:bg-gray-700 disabled:text-gray-500 w-full transition-colors font-semibold"
                    >
                        1. Approve Token
                    </Button>
                    <Button
                        onClick={swapTokens}
                        disabled={!isConnected}
                        className="bg-indigo-600 hover:bg-indigo-700 disabled:bg-gray-700 disabled:text-gray-500 w-full transition-colors font-semibold"
                    >
                        2. Execute Swap
                    </Button>
                </div>

                {/* Instructions */}
                <div className="mt-8 p-4 bg-gray-800 rounded-xl border border-gray-700 text-gray-400">
                    <h3 className="text-sm font-semibold text-gray-300 mb-2">Instructions 🧐</h3>
                    <ol className="text-xs space-y-1 list-decimal list-inside">
                        <li>Start Anvil with: <code className="bg-gray-700 text-gray-300 px-1 rounded text-xs">anvil --fork-url YOUR_MAINNET_RPC</code></li>
                        <li>Connect MetaMask to Anvil network (Chain ID: 31337)</li>
                        <li>Import an Anvil account to MetaMask using a private key</li>
                        <li>Click **"Approve Token"** first, then click **"Execute Swap"**</li>
                    </ol>
                </div>
            </CardContent>
        </Card>
    );
}

export default SwapComponent;
