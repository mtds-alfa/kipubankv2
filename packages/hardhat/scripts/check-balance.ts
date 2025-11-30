import { ethers } from "hardhat";

// Seu endereço da carteira
const WALLET_ADDRESS = "0x3872A24474167c34006e0F39140ABF0A2BcDebe3";

async function main() {
  console.log("Verificando saldo para o endereço:", WALLET_ADDRESS);
  
  // Verificar saldo de ETH
  const ethBalance = await ethers.provider.getBalance(WALLET_ADDRESS);
  console.log("\nSaldo em ETH:", ethers.formatEther(ethBalance), "ETH");
  
  // Verificar saldo de USDC (endereço do contrato USDC na Sepolia)
  const USDC_ADDRESS = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";
  const usdcAbi = [
    "function balanceOf(address owner) view returns (uint256)",
    "function decimals() view returns (uint8)"
  ];
  
  try {
    const usdc = new ethers.Contract(USDC_ADDRESS, usdcAbi, ethers.provider);
    const usdcBalance = await usdc.balanceOf(WALLET_ADDRESS);
    const decimals = await usdc.decimals();
    
    console.log("\nSaldo em USDC:", ethers.formatUnits(usdcBalance, decimals), "USDC");
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : 'Erro desconhecido';
    console.log("\nNão foi possível verificar o saldo de USDC:", errorMessage);
  }
}

main().catch((error) => {
  console.error("Erro:", error);
  process.exitCode = 1;
});