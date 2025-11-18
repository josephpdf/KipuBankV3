# KipuBankV3 – Smart Contract

Bienvenido a **KipuBankV3**, un contrato inteligente desarrollado como parte del *Ethereum Developer Pack (EDP)* de **ETH Kipu – Henry**. 
Este proyecto aplica buenas prácticas de seguridad, patrones de diseño y documentación profesional en Solidity.

---

## 🏦 Descripción del Contrato

**KipuBankV3** es una bóveda bancaria on-chain donde cada usuario puede depositar y retirar fondos utilizando el token nativo de la red. Cada usuario posee su propia "bóveda personal" dentro del contrato.

El contrato cuenta con:

* Límite global de depósitos (bankCap).
* Límite máximo de retiro por transacción (withdrawLimit), definido como `immutable`.
* Registro de depósitos y retiros por usuario.
* Control de seguridad mediante errores personalizados.
* Eventos para operaciones exitosas.
* Manejo seguro de transferencias nativas.
* Buenas prácticas: *checks-effects-interactions*, modificadores, NatSpec y organización clara.

---

## ✨ Funcionalidades Principales

* **Depositar ETH** en la bóveda del usuario.
* **Retirar ETH** respetando un límite fijo por transacción.
* **Respetar un tope global** de depósitos definido en el despliegue.
* **Consultar información** con funciones `view`.
* **Lógica interna encapsulada** en funciones privadas.

---

## 🔒 Seguridad y Buenas Prácticas

Este contrato aplica:

* **Errores personalizados** en lugar de `require` con strings.
* **Patrón checks-effects-interactions** para evitar reentrancy.
* **Uso de `call`** para envío de ETH.
* **Variables `immutable` y `constant`**.
* **Eventos** para mejorar trazabilidad.
* **Modificadores** para validar límites.
* **NatSpec** en funciones, errores y variables.

---

## 🔧 Interacción con el Contrato

### **1. Depositar ETH**

* Llama a la función `deposit()` enviando ETH vía `msg.value`.

### **2. Retirar ETH**

* Usa `withdraw(uint256 amount)`, siempre que:

  * No exceda `withdrawLimit`.
  * Tengas fondos suficientes.

### **3. Consultas (view)**

* `getVaultBalance(address)` – Balance de un usuario.
* `getTotalDeposits()` – Total depositado en el banco.
* `getStats(address)` – Número de depósitos y retiros del usuario.

---

## 📍 Dirección del Contrato Desplegado

> **Testnet:** *Pendiente de completar una vez desplegado*.

Incluye aquí tu dirección cuando ya esté verificada:

```
0x............................................
```

---

## 📘 Tecnología Utilizada

* Solidity ^0.8.x
* Hardhat
* Testnet: Sepolia (según elección)
* MetaMask para interacción
* Ethers.js

---

## 📄 Licencia

Este proyecto se encuentra bajo licencia **MIT**.

---

## 🙌 Autor

**Joseph Poveda**
Desarrollador Web3
