const functions = require("firebase-functions");
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp();

/**
 * Endpoint HTTP para resetar o status de todos os remédios para "off-time".
 * Pode ser acessado manualmente para testes locais.
 */
exports.resetMedicationStatusDaily = functions.https.onRequest(
  async (req, res) => {
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
      const updates = {};

      for (const remId in remedios) {
        if (Object.prototype.hasOwnProperty.call(remedios, remId)) {
          if (remedios[remId].status !== "off-time") {
            updates[`remedios/${remId}/status`] = "off-time";
          }
        }
      }

      if (Object.keys(updates).length > 0) {
        await userRef.update(updates);
        console.log("Status dos remédios resetados para off-time.");
        res.status(200).send("Status dos remédios resetados para off-time.");
      } else {
        console.log("Nenhum status de remédio para resetar.");
        res.status(200).send("Nenhum status de remédio para resetar.");
      }
    } catch (error) {
      console.error("Erro ao resetar status dos remédios:", error);
      res.status(500).send("Erro interno do servidor.");
    }
  }
);
