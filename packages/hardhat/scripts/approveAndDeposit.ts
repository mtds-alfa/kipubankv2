import { ethers } from "hardhat";
import { formatEther, formatUnits, parseEther, parseUnits } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

async function main() {
  console.log("🚀 Iniciando script de aprovação e depósito...");

  // 1. Obter signer (conta que fará as transações)
  const [signer] = await ethers.getSigners();
  console.log(`\n🔑 Conta conectada: ${signer.address}`);

  // 2. Configurações (substitua pelos valores corretos)
  const KIPU_BANK_ADDRESS = "0x..."; // Endereço do contrato KipuBankV2
  const TOKEN_ADDRESS = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"; // USDC na Sepolia
  const TOKEN_DECIMALS = 6; // USDC tem 6 decimais
  const AMOUNT_TO_DEPOSIT = "10"; // Quantidade de tokens para depositar

  // 3. Verificar saldo de ETH para taxas de gás
  const ethBalance = await ethers.provider.getBalance(signer.address);
  console.log(`💰 Saldo de ETH: ${formatEther(ethBalance)} ETH`);
  
  if (ethBalance < parseEther("0.01")) {
    console.error("❌ Saldo de ETH insuficiente para cobrir as taxas de gás");
    process.exit(1);
  }

  // 4. Obter instância do token
  console.log("\n🔄 Obtendo instância do token...");
  const token = await ethers.getContractAt(
    [
      "function approve(address spender, uint256 amount) external returns (bool)",
      "function balanceOf(address owner) external view returns (uint256)",
      "function allowance(address owner, address spender) external view returns (uint256)",
      "function decimals() external view returns (uint8)"
    ],
    TOKEN_ADDRESS,
    signer
  );

  // 5. Verificar saldo do token
  const tokenBalance = await token.balanceOf(signer.address);
  const amountToDeposit = parseUnits(AMOUNT_TO_DEPOSIT, TOKEN_DECIMALS);
  
  console.log(`💳 Saldo do token: ${formatUnits(tokenBalance, TOKEN_DECIMALS)}`);
  
  if (tokenBalance < amountToDeposit) {
    console.error(`❌ Saldo insuficiente. Necessário: ${AMOUNT_TO_DEPOSIT}, Disponível: ${formatUnits(tokenBalance, TOKEN_DECIMALS)}`);
    process.exit(1);
  }

  // 6. Verificar permissão existente
  const kipuBank = await ethers.getContractAt("KipuBankV2", KIPU_BANK_ADDRESS, signer);
  const currentAllowance = await token.allowance(signer.address, KIPU_BANK_ADDRESS);
  
  console.log(`\n🔍 Verificando permissão...`);
  console.log(`Permissão atual: ${formatUnits(currentAllowance, TOKEN_DECIMALS)}`);

  // 7. Aprovar se necessário
  if (currentAllowance < amountToDeposit) {
    console.log("\n🔒 Aprovando tokens para o KipuBankV2...");
    try {
const approveTx = await token.approve(KIPU_BANK_ADDRESS, ethers.MaxUint256);
      console.log(`⏳ Aguardando confirmação da aprovação... (${approveTx.hash})`);
      await approveTx.wait();
      console.log("✅ Aprovação confirmada!");
    } catch (error) {
      console.error("❌ Erro ao aprovar tokens:", error);
      process.exit(1);
    }
  } else {
    console.log("✅ Permissão suficiente já concedida");
  }

  // 8. Fazer o depósito
  console.log("\n💰 Fazendo depósito...");
  try {
    const depositTx = await kipuBank.deposit(TOKEN_ADDRESS, amountToDeposit);
    console.log(`⏳ Aguardando confirmação do depósito... (${depositTx.hash})`);
    const receipt = await depositTx.wait();
    
    // Verificar se o depósito foi bem-sucedido
    const receiptWithLogs = await ethers.provider.getTransactionReceipt(depositTx.hash);
    const iface = kipuBank.interface;
    const depositEvent = receiptWithLogs?.logs
      .map(log => {
        try {
          return iface.parseLog({ data: log.data, topics: [...log.topics] });
        } catch (e) {
          return null;
        }
      })
      .find(e => e?.name === 'Deposited');
      
    if (depositEvent) {
      console.log("✅ Depósito realizado com sucesso!");
      console.log(`   - Token: ${depositEvent.args[0]}`);
      console.log(`   - Quantidade: ${formatUnits(depositEvent.args[1], TOKEN_DECIMALS)}`);
      console.log(`   - Valor em USD: $${formatUnits(depositEvent.args[2], 8)}`);
    } else {
      console.log("⚠️ Depósito enviado, mas não foi possível verificar o evento de confirmação");
    }
  } catch (error) {
    console.error("❌ Erro ao fazer depósito:", error);
    process.exit(1);
  }

  // 9. Verificar saldo atualizado
  console.log("\n🔄 Verificando saldo atualizado...");
  const newBalance = await kipuBank.getBalance(TOKEN_ADDRESS, signer.address);
  console.log(`🏦 Novo saldo no KipuBank: ${formatUnits(newBalance, TOKEN_DECIMALS)}`);
  
  console.log("\n✨ Processo concluído com sucesso!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Erro inesperado:", error);
    process.exit(1);
  });
