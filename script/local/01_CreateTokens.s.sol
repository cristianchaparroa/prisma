// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/**
 * @title Mock ERC20 Token for Testing
 * @notice Enhanced ERC20 with minting and burning for testing
 */
contract MockERC20 is ERC20 {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol, decimals_) {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function faucet(uint256 amount) external {
        require(amount <= 1000 * 10 ** decimals, "Too much tokens");
        _mint(msg.sender, amount);
    }
}

/**
 * @title Create Test Tokens
 * @notice Creates all necessary tokens for testing the yield maximizer
 */
contract CreateTokens is Script {
    // Token contracts
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public wbtc;
    MockERC20 public yieldToken;

    // Token configuration
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply; // In token units (will be multiplied by 10^decimals)
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Creating test tokens...");
        console.log("Deployer:", deployer);

        // Define token configurations
        TokenConfig[5] memory configs = [
            TokenConfig("Wrapped Ether", "WETH", 18, 10_000), // 10,000 WETH
            TokenConfig("USD Coin", "USDC", 6, 10_000_000), // 10M USDC
            TokenConfig("Dai Stablecoin", "DAI", 18, 10_000_000), // 10M DAI
            TokenConfig("Wrapped Bitcoin", "WBTC", 8, 1_000), // 1,000 WBTC
            TokenConfig("Yield Token", "YIELD", 18, 100_000_000) // 100M YIELD
        ];

        // Deploy tokens
        weth = _deployToken(configs[0], deployer);
        usdc = _deployToken(configs[1], deployer);
        dai = _deployToken(configs[2], deployer);
        wbtc = _deployToken(configs[3], deployer);
        yieldToken = _deployToken(configs[4], deployer);

        console.log("\n=== TOKEN DEPLOYMENT COMPLETE ===");
        _logTokenInfo("WETH", address(weth), weth.decimals(), weth.balanceOf(deployer));
        _logTokenInfo("USDC", address(usdc), usdc.decimals(), usdc.balanceOf(deployer));
        _logTokenInfo("DAI", address(dai), dai.decimals(), dai.balanceOf(deployer));
        _logTokenInfo("WBTC", address(wbtc), wbtc.decimals(), wbtc.balanceOf(deployer));
        _logTokenInfo("YIELD", address(yieldToken), yieldToken.decimals(), yieldToken.balanceOf(deployer));

        vm.stopBroadcast();

        // Save token addresses
        _saveTokenAddresses();
    }

    function _deployToken(TokenConfig memory config, address deployer) internal returns (MockERC20) {
        MockERC20 token = new MockERC20(config.name, config.symbol, config.decimals);

        // Mint initial supply to deployer
        uint256 supply = config.initialSupply * 10 ** config.decimals;
        token.mint(deployer, supply);

        console.log("Deployed", config.symbol, "at:", address(token));
        console.log("  Initial supply:", supply / 10 ** config.decimals, config.symbol);

        return token;
    }

    function _logTokenInfo(string memory symbol, address tokenAddress, uint8 decimals_, uint256 balance)
        internal
        pure
    {
        console.log(symbol, ":", tokenAddress);
        console.log("  Balance:", balance / 10 ** decimals_, symbol);
    }

    function _saveTokenAddresses() internal {
        string memory tokenAddresses = string.concat(
            "WETH=",
            vm.toString(address(weth)),
            "\n",
            "USDC=",
            vm.toString(address(usdc)),
            "\n",
            "DAI=",
            vm.toString(address(dai)),
            "\n",
            "WBTC=",
            vm.toString(address(wbtc)),
            "\n",
            "YIELD=",
            vm.toString(address(yieldToken)),
            "\n"
        );

        vm.writeFile("./deployments/tokens.env", tokenAddresses);
        console.log("\nToken addresses saved to: ./deployments/tokens.env");
    }
}
