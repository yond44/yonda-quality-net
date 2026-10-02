import api from "./api";
import type { Vacancy, VacancySkill, PaginationMeta } from "@/types";

export interface VacancyPayload {
  role_title: string;
  culture_dimensions: string;
  competency_expectations: string;
  vacancy_skills_attributes: Partial<VacancySkill>[];
}

export const vacanciesApi = {
  list: (page = 1) =>
    api.get<{ vacancies: Vacancy[]; meta: PaginationMeta }>("/vacancies", {
      params: { page },
    }),

  // Every vacancy of the company, page by page (the API returns at most 100 at a time).
  // For choices that must offer all of them, such as the fit/gap vacancy (audit F35).
  listAll: async (): Promise<Vacancy[]> => {
    const all: Vacancy[] = [];
    for (let page = 1; ; page++) {
      const res = await api.get<{ vacancies: Vacancy[]; meta: PaginationMeta }>("/vacancies", {
        params: { page, per_page: 100 },
      });
      all.push(...res.data.vacancies);
      if (page >= (res.data.meta?.total_pages ?? 1)) return all;
    }
  },

  get: (id: number) =>
    api.get<{ vacancy: Vacancy }>(`/vacancies/${id}`),

  create: (data: VacancyPayload) =>
    api.post<{ vacancy: Vacancy }>("/vacancies", { vacancy: data }),

  update: (id: number, data: VacancyPayload) =>
    api.put<{ vacancy: Vacancy }>(`/vacancies/${id}`, { vacancy: data }),

  delete: (id: number) => api.delete(`/vacancies/${id}`),
};
