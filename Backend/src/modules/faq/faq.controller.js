const { faqService } = require('./faq.service');

function handle(action) {
  return async (req, res, next) => {
    try {
      const { status = 200, data } = await action(req);
      res.status(status).json({ ok: true, data });
    } catch (error) {
      next(error);
    }
  };
}

module.exports = {
  listPublic: handle(async (req) => ({ data: await faqService.listFaqs({
    categoryId: req.query.categoriaId, search: req.query.search,
  }) })),
  listAdmin: handle(async (req) => ({ data: await faqService.listFaqs({
    categoryId: req.query.categoriaId, search: req.query.search, admin: true,
  }) })),
  listCategories: handle(async () => ({ data: await faqService.listCategories() })),
  getPublic: handle(async (req) => ({ data: await faqService.getPublicFaq(req.params.id) })),
  createFaq: handle(async (req) => ({ status: 201, data: await faqService.createFaq(req.body, req.auth.userId) })),
  updateFaq: handle(async (req) => ({ data: await faqService.updateFaq(req.params.id, req.body, req.auth.userId) })),
  setFaqStatus: handle(async (req) => ({ data: await faqService.setFaqStatus(req.params.id, req.body.activa, req.auth.userId) })),
  deleteFaq: handle(async (req) => ({ data: await faqService.deleteFaq(req.params.id, req.auth.userId) })),
  createCategory: handle(async (req) => ({ status: 201, data: await faqService.createCategory(req.body, req.auth.userId) })),
  updateCategory: handle(async (req) => ({ data: await faqService.updateCategory(req.params.id, req.body, req.auth.userId) })),
  deleteCategory: handle(async (req) => ({ data: await faqService.deleteCategory(req.params.id, req.auth.userId) })),
};
