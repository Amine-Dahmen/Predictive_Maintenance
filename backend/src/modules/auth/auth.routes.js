const router = require("express").Router();
const ctrl = require("./auth.controller");
const schemas = require("./auth.schemas");
const validate = require("../../middlewares/validate");
const { authenticate } = require("../../middlewares/auth");
const { loginLimiter } = require("../../middlewares/rateLimit");
const h = require("../../utils/asyncHandler");

router.post(
  "/login",
  loginLimiter,
  validate({ body: schemas.login }),
  h(ctrl.login),
);
router.post("/refresh", validate({ body: schemas.refresh }), h(ctrl.refresh));
router.post("/logout", validate({ body: schemas.refresh }), h(ctrl.logout));

// Accessibles même si le mot de passe provisoire n'a pas encore été changé
router.get(
  "/me",
  authenticate({ allowPasswordChangePending: true }),
  h(ctrl.me),
);
router.patch(
  "/me",
  authenticate({ allowPasswordChangePending: true }),
  validate({ body: schemas.updateProfile }),
  h(ctrl.updateProfile),
);
router.post(
  "/change-password",
  authenticate({ allowPasswordChangePending: true }),
  validate({ body: schemas.changePassword }),
  h(ctrl.changePassword),
);

module.exports = router;
