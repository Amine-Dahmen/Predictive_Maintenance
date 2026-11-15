const { z, password } = require('../../utils/schemas');

const login = z.object({
  email: z.string().trim().toLowerCase().email('E-mail invalide'),
  motDePasse: z.string().min(1, 'Mot de passe obligatoire').max(100),
});

const refresh = z.object({ refreshToken: z.string().min(20).max(200) });

const changePassword = z.object({
  ancienMotDePasse: z.string().min(1).max(100),
  nouveauMotDePasse: password,
}).refine((d) => d.ancienMotDePasse !== d.nouveauMotDePasse, {
  message: "Le nouveau mot de passe doit être différent de l'ancien", path: ['nouveauMotDePasse'],
});

const updateProfile = z.object({
  telephone: z.string().trim().max(30).nullable().optional(),
}).refine((data) => Object.hasOwn(data, 'telephone'), 'Aucun champ à modifier');

module.exports = { login, refresh, changePassword, updateProfile };
