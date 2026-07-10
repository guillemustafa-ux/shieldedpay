// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFlaggedRegistry} from "./interfaces/IFlaggedRegistry.sol";

/// @title FlaggedRegistry — registro on-chain de commitments marcados como sucios
/// @notice Colapso on-chain de la salida del screening de Layer 1 (el taint
///         analysis sobre el grafo público de depósitos). En el diseño completo
///         (ver docs/DECENTRALIZED-ASP.md), Layer 1 propaga taint desde una lista
///         de fuentes marcadas (Layer 4) y marca todo depósito cuya procedencia
///         traza a una fuente sucia. Esa propagación NO es recomputable on-chain
///         (recorrer el grafo entero de transacciones es inviable en un contrato),
///         así que la colapsamos a este registro: el RESULTADO del análisis
///         (qué commitments quedaron marcados) queda publicado on-chain, y sobre
///         él el ASPRegistry monta el fraud proof de permisividad
///         (challengeInclusion): probar que un ASP incluyó un commitment marcado
///         en su set "limpio" es slasheable.
///
/// @dev STUB DE LAYER 4 — attester ÚNICO. Acá el `owner` es un attester único que
///      publica el resultado del taint analysis. En el diseño real esto NO es un
///      owner único: son ATTESTATIONS (p.ej. EAS) de attesters IDENTIFICADOS, cada
///      ASP declara en su `policyHash` qué attesters honra, y las marcas pasan por
///      VENTANAS DE DISPUTA antes de propagar (optimistic: marcado salvo que se
///      dispute con éxito). unflag() existe justamente para modelar esa reversión:
///      si una marca se disputa/revierte, el attester la levanta. La generalización
///      a múltiples attesters por-ASP es el trabajo futuro de Layer 4 documentado.
contract FlaggedRegistry is Ownable, IFlaggedRegistry {
    /// @notice commitment => marcado como sucio. `false` (default) => limpio.
    mapping(uint256 => bool) public isFlagged;

    /// @param commitment Commitment marcado como sucio.
    event Flagged(uint256 indexed commitment);

    /// @param commitment Commitment cuya marca fue levantada (disputa/reversión).
    event Unflagged(uint256 indexed commitment);

    /// @param attester Dueño del registro: el attester que publica el resultado del
    ///        screening. En el diseño real, un conjunto de attesters con disputas
    ///        (Layer 4), no un owner único (ver NatSpec de cabecera).
    constructor(address attester) Ownable(attester) {}

    /// @notice Marca un commitment como sucio (salida del taint analysis).
    /// @dev Idempotente: re-marcar algo ya marcado emite igual (no rompe invariantes).
    /// @param commitment Commitment a marcar.
    function flag(uint256 commitment) external onlyOwner {
        isFlagged[commitment] = true;
        emit Flagged(commitment);
    }

    /// @notice Marca en lote varios commitments como sucios.
    /// @dev Conveniencia para publicar el resultado del screening de un batch.
    /// @param commitments Lista de commitments a marcar.
    function flagBatch(uint256[] calldata commitments) external onlyOwner {
        for (uint256 i = 0; i < commitments.length; i++) {
            isFlagged[commitments[i]] = true;
            emit Flagged(commitments[i]);
        }
    }

    /// @notice Levanta la marca de un commitment (por si se disputa/revierte).
    /// @dev Modela la ventana de disputa de Layer 4: una marca puede revertirse si
    ///      el flagging se impugna con éxito.
    /// @param commitment Commitment a desmarcar.
    function unflag(uint256 commitment) external onlyOwner {
        isFlagged[commitment] = false;
        emit Unflagged(commitment);
    }
}
