const functions = require("firebase-functions");
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp();

/**
 * Endpoint HTTP para resetar o status de todos os remédios para "off-time".
 * Pode ser acessado manualmente para testes locais.
 */
exports.countMedicationStatus = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.database();
    const userRef = db.ref("user_test");
    const userSnapshot = await userRef.once("value");
    const user = userSnapshot.val();

    if (!user || !user.remedios) {
      console.log("Nenhum usuário ou remédios encontrados.");
      res.status(200).send("Nenhum usuário ou remédios encontrados.");
      return;
    }

    const remedios = user.remedios;

    // Zera os contadores locais
    let onTimeCount = 0;
    let offTimeCount = 0;
    let lateTimeCount = 0;

    // Conta cada status
    for (const remId in remedios) {
      if (Object.prototype.hasOwnProperty.call(remedios, remId)) {
        const status = remedios[remId].status;
        if (status === "off-time") offTimeCount++;
        else if (status === "on-time") onTimeCount++;
        else if (status === "late-time") lateTimeCount++;
      }
    }

    // Atualiza os contadores na base
    await userRef.update({
      onTime: onTimeCount,
      offTime: offTimeCount,
      lateTime: lateTimeCount
    });

      console.log("Contagem de status concluída com sucesso.");
      res.status(200).send("Contagem de status concluída com sucesso.");
    } catch (error) {
      console.error("Erro ao contar status dos remédios:", error);
      res.status(500).send("Erro interno do servidor.");
    }
  }
);

